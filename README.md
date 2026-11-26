# EAC Vision per iPhone

Client iOS per **EAC Vision Home Assistant** e **EAC Vision AI Home Assistant**. Interfaccia rinnovata in stile app moderna: navigazione a schede in basso (Live, Registrazioni, Eventi, Impostazioni), sfondo sfumato blu scuro, pannelli in vetro, chip di comando e feedback aptico. Mostra le camere ONVIF selezionate nella vista, live HLS con audio nella vista singola, registrazioni H24 con anteprima durante lo scorrimento e gli eventi della versione AI.

## Novità 1.2.4

- In Impostazioni → Visualizzazione puoi mostrare o nascondere i nomi nella griglia e l'orario nella schermata Live.
- La ricerca all'indietro nelle registrazioni usa meno ricerche esatte e un'anteprima più leggera. Il lettore di anteprima viene liberato quando termini lo scorrimento.
- Con EAC Vision AI 0.1.14 o EAC Vision senza AI 0.5.6, i vecchi MP4 H.265 marcati `hev1` sono serviti all'iPhone come `hvc1` senza ricodificare il video.

## Novità 1.2.3

- Le notifiche inviate dagli add-on Home Assistant aggiornati aprono direttamente il live della telecamera nell'app iPhone quando la tocchi. Serve EAC Vision AI 0.1.13 o EAC Vision senza AI 0.5.5 e una connessione già configurata nell'app.
- Con l'add-on AI, la linea delle registrazioni evidenzia i picchi del volume audio; le barre si popolano via via che l'add-on analizza i file completati.

## Novità 1.2.2

- Il salto da un evento AI recente aspetta la registrazione corrispondente e la apre automaticamente appena il segmento viene chiuso, senza avviare un video precedente.
- Nelle registrazioni viene segnalato quando il profilo ONVIF della telecamera non fornisce una traccia audio. Le nuove registrazioni includono l'audio solo se la telecamera lo invia.

## Novità 1.2.1

- Schermata **Registrazioni** ricostruita: selezione della camera e del giorno, video grande, comandi di riproduzione, audio, velocità e zoom raccolti in modo chiaro.
- Timeline unica delle 24 ore con tratti registrati, cursore ed eventi colorati. Trascinando sulla linea, l'anteprima appare nello stesso riquadro del video; al rilascio parte la riproduzione dall'ora scelta.
- Elenco degli eventi del giorno con accesso al video da cinque secondi prima; pulsante "Ultima" per andare all'ultima registrazione disponibile.
- Nella vista singola della camera il pulsante si chiama **Registrazioni**.

## Novità 1.2.0

- **Navigazione a schede**: Live / Registrazioni / Eventi / Impostazioni sempre raggiungibili dalla barra in basso.
- **Griglia personalizzabile**: oltre alle viste dell'NVR puoi scegliere la griglia locale con 1, 2 o 3 colonne (menu "Griglia" sopra la griglia).
- **Foto dalla vista camera**: pulsante "Foto" per salvare l'istantanea nella Libreria foto e voce "Condividi la foto" nel menu Altro.
- **Eventi potenziati**: filtri per tipo (persona, animale, veicolo, movimento) e per camera, percentuale di affidabilità sulla scheda e pulsante "Guarda" che apre le registrazioni direttamente al momento dell'evento.
- **Velocità di riproduzione fino a 16×** nell'archivio (prima si fermava a 4×).
- Pannelli traslucidi in vetro, badge REC/LIVE/SNAP più leggibili e piccoli effetti di pressione con feedback aptico sui tasti.
- In Impostazioni: versione dell'app, nome del registratore e pulsante "Disconnetti".

## Collegamento

- Aggiorna l'app Home Assistant: edizione senza AI **0.5.4** o edizione AI **0.1.11**. Le nuove registrazioni includono l'audio se la camera lo fornisce; gli avvisi facoltativi tramite Home Assistant Companion sono disponibili in entrambe le edizioni.
- In casa puoi inserire l'IP o l'URL di Home Assistant, anche con `:8123`: l'app prova automaticamente le porte 8766 (senza AI) e 8767 (AI).
- Con Tailscale attivo su iPhone e sul dispositivo HA, inserisci l'IP `100.x.y.z` del dispositivo HA. Se la connessione non riesce, apri `http://100.x.y.z:8766/eacnvr/info` in Safari (o `:8767` per AI) per verificare la porta; non serve il codice per questa verifica.
- Inserisci il codice delle app mostrato nelle impostazioni di EAC Vision su HA. Il codice viene conservato nel portachiavi iOS.
- Con DuckDNS serve un proxy HTTPS verso `/eacnvr/`, con supporto HLS/MP4 e WebSocket. Il normale URL di Home Assistant sulla porta 8123 non basta.

Il live prova HLS/fMP4 e poi HLS/TS. Se il lettore nativo non riceve un fotogramma, l'app continua a mostrare le istantanee della camera invece di lasciare lo schermo nero e segnala il problema nella vista singola. La griglia mostra fino a quattro camere in diretta; le altre si aggiornano con istantanee e si aprono in diretta toccandole, per evitare troppi decoder simultanei sul telefono e sul registratore. Il video H.264/H.265 e l'audio dipendono dai codec della telecamera e dal modello di iPhone. Le registrazioni usano i file MP4 dell'archivio EAC Vision: la timeline copre l'intera giornata, mostra un'anteprima mentre sposti il cursore, indica gli eventi AI con segni colorati (persone arancione, animali verde, veicoli viola) o il movimento ONVIF in grigio nella versione senza AI, e passa automaticamente al file successivo durante la riproduzione.

Nel live e nelle registrazioni puoi ingrandire con due dita, trascinare l'immagine ingrandita e usare il doppio tocco per ingrandire o tornare alla vista completa. Nella vista singola, uno scorrimento orizzontale cambia camera quando lo zoom è disattivato. Dalla vista singola puoi avviare la ronda delle camere nella vista corrente, passare alla precedente o successiva; in Impostazioni scegli l'intervallo e l'avvio automatico. Nell'archivio puoi attivare o silenziare l'audio, scegliere una velocità da 0,5× a 16× (la velocità effettiva dipende dal video e dal lettore iOS), ingrandire il video fino a 6× e saltare direttamente agli eventi rilevati. Durante lo scorrimento della giornata l'anteprima riproduce il video senza audio. Con un NVR PC che espone le capacità EZVIZ, la vista singola offre PTZ e sirena. Il comando Parla richiede un canale audio bidirezionale, attualmente non esposto dal servizio NVR all'app iPhone.

In **Impostazioni → Notifiche di rilevamento** puoi scegliere un dispositivo Home Assistant Companion e abilitare i tipi di evento disponibili. Questo è un canale facoltativo; gli avvisi a EAC Vision chiusa arrivano nell'app Home Assistant Companion. Per riceverli direttamente nell'app iPhone occorrono APNs, un'app firmata con la capacità push e un servizio che invia le notifiche.

## Build e IPA

Scarica l'IPA più recente dalla [pagina delle release](https://github.com/gianni7779/eac-vision-ios/releases).

Il progetto SwiftUI è definito in `project.yml` per XcodeGen. Il workflow GitHub Actions compila su macOS e produce `EACVision-unsigned.ipa` come artifact. **L'IPA non è firmata**: iOS richiede una firma valida per installarla. Per un'IPA direttamente installabile bisogna firmarla con un certificato/profilo Apple del proprietario oppure firmare localmente l'IPA con uno strumento di sideload autorizzato dal dispositivo. Non inserire credenziali Apple nel repository.

Il codice sorgente contiene la versione iPhone; non modifica le versioni Android, PC o TV.
