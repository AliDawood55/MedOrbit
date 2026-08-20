const crypto=require('crypto');
const db=require('../config/database');
const env=require('../config/env');
const {buildEnvelope}=require('../events/eventEnvelope');

const BACKOFF_MS=[5000,15000,60000,300000,900000];
const safeError=(error)=>String(error?.message||'Kafka publish failed').replace(/(?:password|token|secret|credential)=?[^\s,;]*/gi,'[redacted]').slice(0,500);
const backoffMs=(attempt)=>BACKOFF_MS[Math.min(Math.max(attempt-1,0),BACKOFF_MS.length-1)];

class OutboxPublisher{
 constructor({pool=db.pool,producer,workerId=`outbox-${crypto.randomUUID()}`,batchSize=env.kafka.batchSize,lockTimeoutMs=env.kafka.lockTimeoutMs,maxAttempts=env.kafka.maxAttempts,afterPublish=null}={}){
  this.pool=pool;this.producer=producer;this.workerId=workerId;this.batchSize=batchSize;this.lockTimeoutMs=lockTimeoutMs;this.maxAttempts=maxAttempts;this.afterPublish=afterPublish;this.connected=false;
 }
 async connect(){await this.producer.connect();this.connected=true;}
 async disconnect(){this.connected=false;await this.producer.disconnect();}
 async claimBatch(){const client=await this.pool.connect();try{await client.query('BEGIN');
   await client.query(`UPDATE medorbit.outbox_events SET status='failed',locked_at=NULL,locked_by=NULL,available_at=NOW(),updated_at=NOW(),last_error='stale publisher lock recovered'
    WHERE status='publishing' AND locked_at < NOW()-($1::bigint*interval '1 millisecond')`,[this.lockTimeoutMs]);
   const claimed=await client.query(`WITH candidates AS (
      SELECT id FROM medorbit.outbox_events WHERE status IN ('pending','failed') AND available_at<=NOW()
      ORDER BY available_at,created_at FOR UPDATE SKIP LOCKED LIMIT $1)
    UPDATE medorbit.outbox_events o SET status='publishing',attempt_count=o.attempt_count+1,locked_at=NOW(),locked_by=$2,updated_at=NOW()
    FROM candidates c WHERE o.id=c.id RETURNING o.*`,[this.batchSize,this.workerId]);
   await client.query('COMMIT');return claimed.rows;
  }catch(error){await client.query('ROLLBACK');throw error;}finally{client.release();}}
 async markPublished(row){await this.pool.query(`UPDATE medorbit.outbox_events SET status='published',published_at=NOW(),locked_at=NULL,locked_by=NULL,last_error=NULL,updated_at=NOW() WHERE id=$1 AND status='publishing' AND locked_by=$2`,[row.id,this.workerId]);}
 async markFailed(row,error){const dead=row.attempt_count>=this.maxAttempts,delay=backoffMs(row.attempt_count);
  await this.pool.query(`UPDATE medorbit.outbox_events SET status=$3,available_at=NOW()+($4::bigint*interval '1 millisecond'),locked_at=NULL,locked_by=NULL,last_error=$5,updated_at=NOW() WHERE id=$1 AND status='publishing' AND locked_by=$2`,
   [row.id,this.workerId,dead?'dead':'failed',delay,safeError(error)]);}
 async publishRow(row){try{const envelope=buildEnvelope(row);await this.producer.send({topic:row.kafka_topic,acks:-1,messages:[{key:row.partition_key||row.aggregate_id||row.id,value:JSON.stringify(envelope),headers:Object.fromEntries(Object.entries(row.headers||{}).map(([k,v])=>[k,String(v)]))}]});
   if(this.afterPublish)await this.afterPublish(row,envelope);await this.markPublished(row);return true;
  }catch(error){await this.markFailed(row,error);return false;}}
 async runOnce(){const rows=await this.claimBatch();for(const row of rows)await this.publishRow(row);return rows.length;}
}
module.exports={OutboxPublisher,safeError,backoffMs};
