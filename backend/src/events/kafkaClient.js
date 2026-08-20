const {Kafka,logLevel}=require('kafkajs');
const env=require('../config/env');

function createKafka(clientId=env.kafka.clientId){
 return new Kafka({clientId,brokers:env.kafka.brokers,logLevel:logLevel.WARN,retry:{initialRetryTime:300,retries:8}});
}
async function ensureTopics(kafka,topics=[env.kafka.outboxTopic]){
 const admin=kafka.admin();await admin.connect();try{const existing=new Set(await admin.listTopics()),missing=topics.filter(topic=>!existing.has(topic));
  if(missing.length)await admin.createTopics({waitForLeaders:true,topics:missing.map(topic=>({topic,numPartitions:3,replicationFactor:1}))});
 }finally{await admin.disconnect();}
}
module.exports={createKafka,ensureTopics};
