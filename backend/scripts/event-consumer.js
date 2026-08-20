const env=require('../src/config/env');
const {createKafka}=require('../src/events/kafkaClient');
const {observeEvent}=require('../src/workers/eventObserver');
const {validateEnvelope}=require('../src/events/eventEnvelope');
const {createWorkerHealth}=require('../src/workers/workerHealth');

if(!env.kafka.enabled){console.log('Event consumer disabled (KAFKA_ENABLED=false)');process.exit(0);}
const state={connected:false,lastError:null},health=createWorkerHealth(Number(process.env.WORKER_HEALTH_PORT)||3003,state),kafka=createKafka(`${env.kafka.clientId}-observer`);
const consumer=kafka.consumer({groupId:env.kafka.consumerGroup,allowAutoTopicCreation:false});let stopping=false;
async function shutdown(signal){if(stopping)return;stopping=true;console.log(`Event consumer stopping (${signal})`);try{await consumer.disconnect();}catch{}health.close(()=>process.exit(0));}
process.on('SIGTERM',()=>shutdown('SIGTERM'));process.on('SIGINT',()=>shutdown('SIGINT'));
(async()=>{await consumer.connect();await consumer.subscribe({topic:env.kafka.outboxTopic,fromBeginning:false});state.connected=true;
 await consumer.run({eachMessage:async({message})=>{try{const envelope=validateEnvelope(JSON.parse(message.value.toString('utf8')));await observeEvent('event-observer-v1',envelope);state.lastError=null;}catch(error){state.lastError=String(error.message||error).slice(0,200);console.error('Event rejected:',state.lastError);}}});
})().catch(error=>{state.connected=false;state.lastError=String(error.message||error).slice(0,200);console.error('Event consumer fatal:',state.lastError);
 health.close(()=>process.exit(1));
});
