const env=require('../src/config/env');
const {createKafka}=require('../src/events/kafkaClient');
const {processRecommendationEnvelope}=require('../src/services/recommendationProjection.service');
const {createWorkerHealth}=require('../src/workers/workerHealth');

if(!env.kafka.enabled){console.log('Recommendation consumer disabled (KAFKA_ENABLED=false)');process.exit(0);}
const state={connected:false,lastError:null,processedCount:0,ignoredCount:0,errorCount:0,lastProcessedAt:null};
const health=createWorkerHealth(Number(process.env.WORKER_HEALTH_PORT)||3004,state);
const kafka=createKafka(`${env.kafka.clientId}-recommendation`);
const consumer=kafka.consumer({groupId:env.kafka.recommendationConsumerGroup,allowAutoTopicCreation:false});
let stopping=false;
async function shutdown(signal){if(stopping)return;stopping=true;console.log(`Recommendation consumer stopping (${signal})`);try{await consumer.disconnect();}catch{}health.close(()=>process.exit(0));}
process.on('SIGTERM',()=>shutdown('SIGTERM'));process.on('SIGINT',()=>shutdown('SIGINT'));

(async()=>{
 await consumer.connect();await consumer.subscribe({topic:env.kafka.outboxTopic,fromBeginning:true});state.connected=true;
 await consumer.run({eachMessage:async({message})=>{
  let envelope;
  try{envelope=JSON.parse(message.value.toString('utf8'));}catch(error){state.errorCount++;state.lastError='Malformed event JSON';console.error('Recommendation event rejected:',state.lastError);return;}
  try{const result=await processRecommendationEnvelope(envelope);if(result.ignored)state.ignoredCount++;if(result.processed){state.processedCount++;state.lastProcessedAt=new Date().toISOString();}state.lastError=null;}
  catch(error){state.errorCount++;state.lastError=String(error.message||error).slice(0,200);if(error.permanent){console.error('Recommendation event rejected:',state.lastError);return;}throw error;}
 }});
})().catch(error=>{state.connected=false;state.lastError=String(error.message||error).slice(0,200);console.error('Recommendation consumer fatal:',state.lastError);health.close(()=>process.exit(1));});
