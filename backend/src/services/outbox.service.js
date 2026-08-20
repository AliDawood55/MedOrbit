const crypto=require('crypto');
const env=require('../config/env');

const FORBIDDEN_KEY=/(password|token|secret|credential|google|message[_-]?body|body|content|diagnosis|medical[_-]?record|prescription|clinical|sdp|ice|candidate|audio|video[_-]?data)/i;
function assertSafe(value,path='payload'){
 if(value===null||['string','number','boolean'].includes(typeof value))return;
 if(Array.isArray(value)){value.forEach((item,index)=>assertSafe(item,`${path}[${index}]`));return;}
 if(typeof value!=='object')throw new Error(`Unsupported outbox value at ${path}`);
 for(const[key,child]of Object.entries(value)){if(FORBIDDEN_KEY.test(key))throw new Error(`Forbidden outbox field: ${key}`);assertSafe(child,`${path}.${key}`);}
}
function validateEvent(event){
 if(!event||typeof event!=='object')throw new Error('Outbox event is required');
 if(!/^[a-z][a-z0-9_.-]{2,149}$/.test(String(event.eventType||'')))throw new Error('Invalid outbox event type');
 if(!/^[a-z][a-z0-9_.-]{1,99}$/.test(String(event.aggregateType||'')))throw new Error('Invalid aggregate type');
 if(!Number.isInteger(event.eventVersion||1)||(event.eventVersion||1)<1)throw new Error('Invalid event version');
 const payload=event.payload||{};assertSafe(payload);assertSafe(event.headers||{},'headers');
 if(Buffer.byteLength(JSON.stringify(payload))>32768)throw new Error('Outbox payload is too large');
}
async function enqueueOutboxEvent(client,event){
 if(!client||typeof client.query!=='function'||typeof client.release!=='function')throw new Error('An existing PostgreSQL transaction client is required');
 validateEvent(event);const id=event.eventId||crypto.randomUUID(),version=event.eventVersion||1;
 const result=await client.query(`INSERT INTO medorbit.outbox_events
  (id,aggregate_type,aggregate_id,event_type,event_version,payload,headers,kafka_topic,partition_key)
  VALUES($1,$2,$3,$4,$5,$6,$7,$8,$9) RETURNING *`,
  [id,event.aggregateType,event.aggregateId||null,event.eventType,version,event.payload||{},event.headers||{},event.kafkaTopic||env.kafka.outboxTopic,event.partitionKey||String(event.aggregateId||id)]);
 return result.rows[0];
}
module.exports={enqueueOutboxEvent,validateEvent,assertSafe};
