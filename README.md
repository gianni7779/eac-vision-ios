# EAC Vision per iPhone

Client iOS per **EAC Vision Home Assistant** e **EAC Vision AI Home Assistant**. La grafica riprende l'app Android: logo, barra superiore, vista delle camere e colori blu/azzurro. Mostra le camere ONVIF selezionate nella vista, live HLS con audio nella vista singola, registrazioni H24 con anteprima durante lo scorrimento e gli eventi della versione AI.

## Collegamento

- Aggiorna l'app Home Assistant: edizione senza AI **0.5.3** o edizione AI **0.1.4**. Queste versioni includono l'audio nelle nuove registrazioni, se disponibile sulla camera. L'edizione AI permette gli avvisi tramite Home Assistant Companion.
- In casa puoi inserire l'IP o l'URL di Home Assistant, anche con `:8123`: l'app prova automaticamente le porte 8766 (senza AI) e 8767 (AI).
- Con Tailscale attivo su iPhone e sul dispositivo HA, inserisci l'IP `100.x.y.z` del dispositivo HA. Se la connessione non riesce, apri `http://100.x.y.z:8766/eacnvr/info` in Safari (o `:8767` per AI) per verificare la porta; non serve il codice per questa verifica.
- Inserisci il codice delle app mostrato nelle impostazioni di EAC Vision su HA. Il codice viene conservato nel portachiavi iOS.
- Con DuckDNS serve un proxy HTTPS verso `/eacnvr/`, con supporto HLS/MP4 e WebSocket. Il normale URL di Home Assistant sulla porta 8123 non basta.

Il live prova HLS/fMP4 e poi HLS/TS. Se il lettore nativo non riceve un fotogramma, l'app continua a mostrare le istantanee della camera invece di lasciare lo schermo nero e segnala il problema nella vista singola. La griglia mostra fino a quattro camere in diretta; le altre si aggiornano con istantanee e si aprono in diretta toccandole, per evitare troppi decoder simultanei sul telefono e sul registratore. Il video H.264/H.265 e l'audio dipendono dai codec della telecamera e dal modello di iPhone. Le registrazioni usano i file MP4 dell'archivio EAC Vision: la timeline copre l'intera giornata, mostra un'anteprima mentre sposti il cursore, indica gli eventi AI con segni colorati (persone arancione, animali verde, veicoli viola) o il movimento ONVIF in grigio nella versione senza AI, e passa automaticamente al file successivo durante la riproduzione.

Puoi cambiare la vista dalla barra sopra la griglia. Toccando una camera nella griglia si apre a schermo intero. Il live e le registrazioni si ingrandiscono con due dita. Nell'archivio puoi attivare o silenziare l'audio, cambiare velocità da 0,5× a 4×, ingrandire il video fino a 4× e saltare direttamente agli eventi rilevati. Durante lo scorrimento della giornata l'anteprima riproduce il video senza audio. Con un NVR PC che espone le capacità EZVIZ, la vista singola offre PTZ e sirena. Il comando Parla richiede un canale audio bidirezionale, attualmente non esposto dal servizio NVR all'app iPhone.

In **Impostazioni → Notifiche di rilevamento** puoi scegliere un dispositivo Home Assistant Companion e abilitare i tipi di evento disponibili. Questo è un canale facoltativo; gli avvisi a EAC Vision chiusa arrivano nell'app Home Assistant Companion. Per riceverli direttamente nell'app iPhone occorrono APNs, un'app firmata con la capacità push e un servizio che invia le notifiche.

## Build e IPA

Scarica l'IPA più recente dalla [pagina delle release](https://github.com/gianni7779/eac-vision-ios/releases).

Il progetto SwiftUI è definito in `project.yml` per XcodeGen. Il workflow GitHub Actions compila su macOS e produce `EACVision-unsigned.ipa` come artifact. **L'IPA non è firmata**: iOS richiede una firma valida per installarla. Per un'IPA direttamente installabile bisogna firmarla con un certificato/profilo Apple del proprietario oppure firmare localmente l'IPA con uno strumento di sideload autorizzato dal dispositivo. Non inserire credenziali Apple nel repository.

Il codice sorgente contiene la versione iPhone; non modifica le versioni Android, PC o TV.
