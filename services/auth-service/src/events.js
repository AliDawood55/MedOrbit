import { Kafka, logLevel } from "kafkajs";

let producer;

async function getProducer() {
  if (!process.env.KAFKA_BROKERS) return null;
  if (!producer) {
    const kafka = new Kafka({
      clientId: "auth-service",
      brokers: process.env.KAFKA_BROKERS.split(","),
      logLevel: logLevel.ERROR,
    });
    producer = kafka.producer();
    await producer.connect();
  }
  return producer;
}

export async function publishEvent(topic, payload) {
  try {
    const p = await getProducer();
    if (!p) return;
    await p.send({
      topic,
      messages: [{ value: JSON.stringify({ ...payload, timestamp: new Date().toISOString() }) }],
    });
  } catch (err) {
    console.error(`failed to publish event to ${topic}:`, err.message);
  }
}
