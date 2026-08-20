const db=require('../config/database');
const {validateEnvelope}=require('../events/eventEnvelope');

async function observeEvent(consumerName,envelope,pool=db.pool){validateEnvelope(envelope);const client=await pool.connect();try{
 await client.query('BEGIN');const inserted=await client.query(`INSERT INTO medorbit.processed_events(consumer_name,event_id,event_type,event_version)
  VALUES($1,$2,$3,$4) ON CONFLICT(consumer_name,event_id) DO NOTHING RETURNING event_id`,[consumerName,envelope.eventId,envelope.eventType,envelope.eventVersion]);
 await client.query('COMMIT');return{processed:!!inserted.rows[0]};
 }catch(error){await client.query('ROLLBACK');throw error;}finally{client.release();}}
module.exports={observeEvent};
