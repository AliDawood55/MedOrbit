const fs = require('fs');
const path = require('path');

class LoggerService {

    getPath(conversationId) {
        const now = new Date();
        const year = now.getFullYear();
        const month = String(now.getMonth() + 1).padStart(2, '0');

        const dir = path.join(
            __dirname,
            '../../../storage/chatbot-logs',
            year.toString(),
            month
        );

        if (!fs.existsSync(dir)) {
            fs.mkdirSync(dir, { recursive: true });
        }

        return path.join(dir, conversationId + '.json');
    }

    log(conversationId, entry) {
        const filePath = this.getPath(conversationId);

        let data = {
            conversation_id: conversationId,
            messages: []
        };

        if (fs.existsSync(filePath)) {
            data = JSON.parse(fs.readFileSync(filePath));
        }

        data.messages.push(entry);

        fs.writeFileSync(filePath, JSON.stringify(data, null, 2));
    }
}

module.exports = new LoggerService();