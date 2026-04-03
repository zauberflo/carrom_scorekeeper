const { onValueCreated } = require("firebase-functions/v2/database");
const admin = require("firebase-admin");

admin.initializeApp();

exports.sendscoreupdate = onValueCreated({
    ref: "/games/{gameId}/rounds/{roundId}",
    instance: "carrom-scorekeeper-default-rtdb",
    region: "europe-west1"
}, async (event) => {
    const gameId = event.params.gameId;
    const newRound = event.data.val();
    
    // Wir holen die aktuellen Gesamtpunkte für die Watch-Anzeige
    const roundsSnap = await admin.database().ref(`/games/${gameId}/rounds`).once('value');
    const allRounds = roundsSnap.val() || {};
    
    let total0 = 0;
    let total1 = 0;
    
    Object.values(allRounds).forEach(r => {
        total0 += (r.points && r.points["0"]) || 0;
        total1 += (r.points && r.points["1"]) || 0;
    });

    const payload = {
        notification: {
            // Der Titel zeigt direkt den Spielstand – man muss die Watch nicht mal berühren!
            title: `🏆 ${total0} : ${total1}`, 
            body: `Letzte Runde: +${newRound.points["0"] || 0} | +${newRound.points["1"] || 0}`,
        },
        topic: gameId 
    };

    return admin.messaging().send(payload);
});