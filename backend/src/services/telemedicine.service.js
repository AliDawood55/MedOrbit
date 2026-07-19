function generateMeetingLink(appointmentId) {

    return `https://meet.jit.si/MedOrbit-${appointmentId}`;

}


module.exports = {
    generateMeetingLink
};