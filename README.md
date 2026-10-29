# Ghosting by CrowStudios

Ghosting associe une application iOS à un serveur Python local sur ton ordinateur pour téléporter la position GPS de ton iPhone en Wi-Fi, sans garder de câble branché.

---

## Comment ça marche ?

1. Tu choisis une ville ou une position dans l'application.
2. L'appli envoie la requête en Wi-Fi à ton ordinateur (`POST /set-location`).
3. Le serveur Python exécute `pymobiledevice3` pour mettre à jour la position GPS de l'iPhone.
