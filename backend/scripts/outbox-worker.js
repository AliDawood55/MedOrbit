const env=require('../src/config/env');
const {Partitioners}=require('kafkajs');
const {createKafka,ensureTopics}=require('../src/events/kafkaClient');
const {OutboxPublisher}=require('../src/workers/outboxPublisher');
const {createWorkerHealth}=require('../src/workers/workerHealth');

if(!env.kafka.enabled){console.log('Outbox worker disabled (KAFKA_ENABLED=false)');process.exit(0);}
const state={connected:false,lastError:null},health=createWorkerHealth(Number(process.env.WORKER_HEALTH_PORT)||3002,state);
const kafka=createKafka(`${env.kafka.clientId}-outbox`),producer=kafka.producer({allowAutoTopicCreation:false,createPartitioner:Partitioners.DefaultPartitioner});
const publisher=new OutboxPublisher({producer});let stopping=false,timer=null;
const delay=(ms)=>new Promise(resolve=>{timer=setTimeout(resolve,ms);});
async function shutdown(signal){if(stopping)return;stopping=true;console.log(`Outbox worker stopping (${signal})`);if(timer)clearTimeout(timer);try{await publisher.disconnect();}catch{}health.close(()=>process.exit(0));}
process.on('SIGTERM',()=>shutdown('SIGTERM'));process.on('SIGINT',()=>shutdown('SIGINT'));
(async()=>{while(!stopping){try{await ensureTopics(kafka);if(!publisher.connected)await publisher.connect();state.connected=true;state.lastError=null;const count=await publisher.runOnce();if(!count)await delay(env.kafka.pollIntervalMs);}catch(error){state.connected=false;state.lastError=String(error.message||error).slice(0,200);console.error('Outbox publisher unavailable:',state.lastError);await delay(Math.max(env.kafka.pollIntervalMs,3000));}}})().catch(error=>{console.error('Outbox worker fatal:',String(error.message||error).slice(0,200));process.exit(1);});
