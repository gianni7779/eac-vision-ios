# EAC Vision per iPhone

Client iOS per **EAC Vision Home Assistant** e **EAC Vision AI Home Assistant**. La grafica riprende l'app Android: logo, barra superiore, vista delle camere e colori blu/azzurro. Mostra le camere ONVIF selezionate nella vista, live HLS con audio nella vista singola, registrazioni H24 con anteprima durante lo scorrimento e gli eventi della versione AI.

## Collegamento

- Aggiorna l'app Home Assistant: edizione senza AI **0.5.2** o edizione AI **0.1.3**. Queste versioni includono il flusso alternativo HLS/TS e gli eventi del giorno per la barra delle registrazioni.
- In casa puoi inserire l'IP o l'URL di Home Assistant, anche con `:8123`: l'app prova automaticamente le porte 8766 (senza AI) e 8767 (AI).
- Con Tailscale attivo su iPhone e sul dispositivo HA, inserisci l'IP `100.x.y.z` del dispositivo HA. Se la connessione non riesce, apri `http://100.x.y.z:8766/eacnvr/info` in Safari (o `:8767` per AI) per verificare la porta; non serve il codice per questa verifica.
- Inserisci il codice delle app mostrato nelle impostazioni di EAC Vision su HA. Il codice viene conservato nel portachiavi iOS.
- Con DuckDNS serve un proxy HTTPS verso `/eacnvr/`, con supporto HLS/MP4 e WebSocket. Il normale URL di Home Assistant sulla porta 8123 non basta.

Il live prova HLS/fMP4 e poi HLS/TS. Se il lettore nativo non riceve un fotogramma, l'app continua a mostrare le istantanee della camera invece di lasciare lo schermo nero e segnala il problema nella vista singola. La griglia mostra fino a quattro camere in diretta; le altre si aggiornano con istantanee e si aprono in diretta toccandole, per evitare troppi decoder simultanei sul telefono e sul registratore. Il video H.264/H.265 e l'audio dipendono dai codec della telecamera e dal modello di iPhone. Le registrazioni usano i file MP4 dell'archivio EAC Vision: la timeline copre l'intera giornata, mostra un'anteprima mentre sposti il cursore, indica gli eventi AI con segni colorati (persone arancione, animali verde, veicoli viola) o il movimento ONVIF in grigio nella versione senza AI, e passa automaticamente al file successivo durante la riproduzione.

## Build e IPA

Scarica l'IPA più recente dalla [pagina delle release](https://github.com/gianni7779/eac-vision-ios/releases).

Il progetto SwiftUI è definito in `project.yml` per XcodeGen. Il workflow GitHub Actions compila su macOS e produce `EACVision-unsigned.ipa` come artifact. **L'IPA non è firmata**: iOS richiede una firma valida per installarla. Per un'IPA direttamente installabile bisogna firmarla con un certificato/profilo Apple del proprietario oppure firmare localmente l'IPA con uno strumento di sideload autorizzato dal dispositivo. Non inserire credenziali Apple nel repository.

Il codice sorgente contiene la versione iPhone; non modifica le versioni Android, PC o TV.
