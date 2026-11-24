# EAC Vision per iPhone

Client iOS per **EAC Vision Home Assistant** e **EAC Vision AI Home Assistant**. Mostra camere ONVIF, live HLS con audio, registrazioni H24 con anteprima durante lo scorrimento e gli eventi della versione AI.

## Collegamento

- Aggiorna l'app Home Assistant alla versione che espone HLS: edizione senza AI **0.5.0** o edizione AI **0.1.0**.
- Con Tailscale attivo su iPhone e sul dispositivo HA, inserisci `http://100.x.y.z:8766` per l'edizione senza AI, oppure `http://100.x.y.z:8767` per quella AI.
- Inserisci il codice delle app mostrato nelle impostazioni di EAC Vision su HA. Il codice viene conservato nel portachiavi iOS.
- Con DuckDNS serve un proxy HTTPS verso `/eacnvr/`, con supporto HLS/MP4 e WebSocket. Il normale URL di Home Assistant sulla porta 8123 non basta.

Il live usa il formato HLS/fMP4 di go2rtc, inoltrato dal componente HA. Il video H.264/H.265 e l'audio dipendono dai codec della telecamera e dal modello di iPhone. Le registrazioni usano i file MP4 dell'archivio EAC Vision: la timeline copre l'intera giornata, mostra un'anteprima mentre sposti il cursore e passa automaticamente al file successivo durante la riproduzione. Gli eventi AI sono disponibili solo nell'edizione AI.

## Build e IPA

Scarica [EACVision-unsigned.ipa](https://github.com/gianni7779/eac-vision-ios/releases/download/v1.0.0-ios-preview/EACVision-unsigned.ipa) dalla release di anteprima.

Il progetto SwiftUI è definito in `project.yml` per XcodeGen. Il workflow GitHub Actions compila su macOS e produce `EACVision-unsigned.ipa` come artifact. **L'IPA non è firmata**: iOS richiede una firma valida per installarla. Per un'IPA direttamente installabile bisogna firmarla con un certificato/profilo Apple del proprietario oppure firmare localmente l'IPA con uno strumento di sideload autorizzato dal dispositivo. Non inserire credenziali Apple nel repository.

Il codice sorgente contiene la versione iPhone; non modifica le versioni Android, PC o TV.
