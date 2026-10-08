# Handoff: performance playback Writer su iPhone

Checkpoint del 8 ottobre 2026. Le correzioni funzionali e la diagnostica sono
incluse nel commit che aggiunge questo documento. **Il problema delle performance
audio non è ancora risolto.** La baseline fisica è parziale; nessuna soluzione
audio è stata scelta o implementata.

## Prompt da incollare nella prossima sessione

```text
Lavora in /Users/francescolacriola/dev/ws/muzician e riprendi esclusivamente il
problema delle performance del playback Writer su iPhone 16 Pro Max.

Leggi AGENTS.md, PRODUCT.md, DESIGN.md e
docs/handoffs/2026-10-08-writer-playback-performance.md. Leggi poi la sezione E,
il record delle review e l'addendum diagnostico del piano
docs/superpowers/plans/2026-10-07-spelling-harmony-replacement-playback.md.
Il documento di handoff contiene misure, artefatti, limiti, comandi e lavoro
ancora da fare. Preserva le correzioni funzionali già committate.

L'utente segnala playback Writer lento e a scatti; l'audition Fretboard/Piano
funziona normalmente. La modalità della build originaria non è verificata.
La diagnostica è pronta, ma il nuovo source_binding e le nuove metriche di
drift non sono ancora stati ricatturati sull'iPhone. Il parser temporaneo è
incompleto e fallisce un test: correggilo e fallo revisionare prima di usarlo.
Non interpretare AudioPlayer.play Future completion come inizio audio udibile.

Procedi prima con raccolta e validazione della baseline approvata, utilizzando
computer e il telefono connesso, senza modificare o cancellare progetti utente.
Ogni subagent deve avere fresh context. Usa GPT-6.1 Sol, reasoning extra high,
per review di piano e baseline; GPT-6 Luna, reasoning extra high, per
implementazione e review indipendenti. Itera con nuovi reviewer fino a PASS.
Il piano diagnostico è già approvato. Se la riparazione richiede un nuovo piano
o un cambiamento di scope, scrivi file/snippet, ottieni la review Sol e poi la
mia approvazione prima di implementare. Dopo l'approvazione procedi autonomamente.

Completa le misure prima di scegliere la riparazione. Ottieni la review Sol
della baseline; correggi solo il collo di bottiglia dimostrato, con diff piccoli
e test su ownership, stop/cancel, restart, durata, overlap e offset strumming.
Ripeti le misure prima/dopo e richiedi una verifica d'ascolto sul telefono prima
di dichiarare il playback risolto. Fretboard/Piano/Song non devono regredire.
Aggiorna la documentazione, esegui format, flutter analyze e i test pertinenti.
Non allentare le soglie dopo una patch fallita, né cambiare backend audio per
ipotesi. Ripristina infine l'app normale e chiudi solo i tool creati per il test.
```

## Stato verificato al checkpoint

- Correzioni funzionali: Harmony esatta anche senza riconoscimento, esclusione
  Fretboard Free da Writer, target Strum occupati nascosti, New project nel menu,
  chiave progetto condivisa con conferma, preferenza globale Sharps/Flats,
  fallback del chord picker per pentatoniche, Replace Harmony e pannelli Saves.
  Review funzionali e controlli UI compact/wide completati nel piano.
- Ultima review indipendente della diagnostica Source/voice identity: **PASS**
  (`review_commit_source_diagnostics_oct8`, fresh Luna extra high).
- Nuove metriche first/last tick e differenza firmata: review **PASS**.
- Verifica finale: **1.309 test Flutter passati**, `flutter analyze --no-pub`
  senza problemi; format sui 125 file Dart modificati/nuovi, zero cambiamenti;
  `git diff --check` pulito. Log locali:
  `/private/tmp/muzician_oct8_checkpoint_test.log` e
  `/private/tmp/muzician_oct8_checkpoint_analyze.log`.
- **Baseline completa, scelta della riparazione, misure dopo patch e ascolto:
  ancora da fare.** L'ultima review Sol approva l'addendum e la raccolta,
  non una baseline completa o una riparazione.

## Codice da leggere

| File | Ruolo |
| --- | --- |
| `lib/profile_writer_playback.dart` | Entrypoint QA isolato, fixture, vere viste Writer/Song/Fretboard/Piano, manifest e capture frame per tentativo |
| `lib/utils/playback_profiling.dart` | Span, identità run/event/voice, contatori, errori di dispatch e score boundary |
| `lib/utils/playback_profile_source.dart` | Source forwarding e preservazione del `voice_id` canonico |
| `lib/utils/playback_profile_frame_timing.dart` | Finestra frame, fence/drain, completezza e target refresh |
| `lib/utils/note_player.dart` | WAV/cache, pool preview e sequenced, configurazione/play/stop |
| `lib/store/songwriter_playback_store.dart` | Preparazione, clock Writer, flatten, dispatch, ownership/cancel |
| `lib/store/song_audio_player_sink.dart` | Preparazione e avvio dei clip registrati |
| `lib/store/song_playback_store.dart` | Confronto con Song e contratti condivisi |

Test diagnostici: `test/utils/playback_profile_source_test.dart`,
`playback_profiling_test.dart`, `playback_profile_frame_timing_test.dart`,
`test/profile_writer_playback_fixture_test.dart`,
`test/store/song_audio_player_sink_profile_test.dart` e
`test/store/songwriter_playback_test.dart`. Ampliare i test solo quando la
riparazione concreta lo richiede.

La nuova Source avvolge `Source.setOnPlayer` originale: MIME inoltrato, delega
una sola volta, errori propagati. `AudioPlayer.play` e i suoi controlli
`desiredState` rimangono attivi. Release passa la Source originale. Il
`voice_id` diagnostico è una stringa canonica; il handle locale sequenced è
registrato separatamente come `sequenced_voice_id`.

## Misure disponibili e loro limiti

Le catture sotto sono precedenti alla nuova Source e alle nuove metriche tick.
Non unire queste sottoserie a nuove catture come se la strumentazione fosse uguale.

Plain Harmony: Cmaj7 MIDI 60/64/67/71, 8 battute, 120 BPM, 16 secondi,
8 eventi, 32 voci preview da 700 ms, nessun clip, overlap atteso 4.

| Cattura | Dispatch evento p95/worst | Completamento play Future p95 rispetto all'onset previsto |
| --- | --- | --- |
| Tagged cold01 | 1,933 ms | 375,811 ms |
| Tagged cold02 | 3,711 ms | 537,389 ms |
| Tagged cold03 | 2,524 ms | 312,953 ms |
| Tagged cold04 | 2,827 ms | 319,172 ms |

Sono osservazioni API, non misure di onset udibile. In 8 campioni nearest-rank
p95 coincide con il massimo. Le cinque tracce tagged cold01–cold05 sono complete;
il riepilogo cold05 non è ancora stato generato. Le quattro analisi elencate
riportano 32 voci completate senza drop/steal/error applicativi. Ciò non misura
eventuali difetti del segnale udibile.

Due prime catture USB non tagged mostrano p95 Future 472,288 ms cold e
279,890 ms warm. I loro run raw sono completi, ma il join manifest/frame è
correttamente indisponibile per mancanza di `run_tag` esplicito. Nella warm,
configure p95 ~5,325 ms, play_request p95 ~277,859 ms nonostante cache WAV/file
calda. È evidenza per approfondire la fase play, non prova della causa nativa.

**Tagged warm01 e warm02 sono troncate:** manca il run end raw. Escluderle dal
conteggio della baseline completa anche se il report applicativo termina.
La finestra di 22 s è stata consumata dal ritardo tra collector READY e tap.
Usare almeno 30 s per 8 battute e ~75 s per una fixture di 60 s.

Frame tagged cold01: 562 campioni, 1,6014% sopra il target di costo a 120 Hz,
worst ~8,65 budget; cold02: 1.022 campioni, 1,17417%, worst ~4,17 budget.
Questi contano costo build/raster sopra 8,333 ms; non dimostrano deadline di
presentazione perse né cadenza ProMotion. Una cattura preliminare separata ha un
frame worst 359 ms: non confondere shader/startup con le sottoserie successive.

## Artefatti e parser incompleto

Archivio locale verificato (43 file QA, indice SHA-256 incluso; fuori da Git):

`/Users/francescolacriola/.codex/visualizations/2026/10/03/01a10404-8a48-75e0-8f24-7bb7c32239b9/muzician-performance-handoff-2026-10-08.zip`

SHA-256 archivio:
`b4e686757b4387ce9e59bc38036c3699a929fdab864f97a3385300721671d89e`.
Estrarlo in una nuova cartella di lavoro, senza sovrascrivere gli originali.
L'archivio è locale a questo Mac e va trasferito separatamente per un altro host.

Originali in `/private/tmp`:

- `muzician_oct8_tagged_plain_cold01_raw.json` … `cold05_raw.json`;
  cartelle omonime senza `_raw.json`, contenenti manifest e report frame.
  Analisi `cold01_analysis.json` … `cold04_analysis.json` con lo stesso prefisso.
- `muzician_oct8_tagged_plain_warm01_raw.json`, `warm02_raw.json` e cartelle
  corrispondenti: evidenza parziale, escluse dalla baseline completa.
- `muzician_oct8_usb_plain_cold01b_raw.json`, `...warm01_raw.json`, analisi
  `...cold01_analysis.json` / `...warm01_analysis.json`, cartelle
  `muzician_oct8_usb_plain_session01` e `...session01_warm`.
- `capture_writer_profile_oct8.dart`: collector VM, review R2 PASS precedente.
  Ripristina gli stream VM, non salva l'URL autorizzato del servizio.
- `parse_writer_profile_oct8.py` e `test_parse_writer_profile_oct8.py`:
  **ultima estensione source-binding R2 interrotta e non approvata**.
  `python3 /private/tmp/test_parse_writer_profile_oct8.py` fallisce
  nell'assert sui player ID mancanti, vicino alla riga 571.

La vecchia revisione del parser per identity/frame era PASS. L'estensione Source
R1 era NOT PASS: accettava identità incompleta e aggregava span falliti insieme
ai misurati. La R2 parziale non è un parser validato. Correggere tramite fresh
Luna, poi fresh Luna reviewer. Pretendere uguaglianza completa di run/event/
voice/player/kind/MIDI su parent play begin, source begin e source end, pairing
univoco, ordine temporale e outcome valido. Missing/failed/ambiguous restano
`null` con motivo; aggregati misurati separati dai task raw e dagli unavailable.
Non modificare retroattivamente raw o inventare tag/end mancanti.

## Telefono e comandi

iPhone 16 Pro Max, iOS 27.0.1 (24A446); ultimo ID
`00008140-001459DE347B001C`. Certificato autorizzato dall'utente e USB con telefono
sbloccato hanno risolto signing e accesso VM. Riscoprire stato/dispositivi prima
di avviare. Xcode 27 è installato; mantenere l'override per processo, senza
cambiare `xcode-select` globale:

```sh
env DEVELOPER_DIR=/Applications/Xcode-27.0.0.app/Contents/Developer flutter devices
env DEVELOPER_DIR=/Applications/Xcode-27.0.0.app/Contents/Developer flutter run --profile \
  -d 00008140-001459DE347B001C -t lib/profile_writer_playback.dart --no-pub \
  --dart-define=WRITER_PROFILE_VIEW=writer \
  --dart-define=WRITER_PROFILE_SCENARIO=plain_harmony \
  --dart-define=WRITER_PROFILE_AUTOSTART=false \
  --dart-define=WRITER_PROFILE_DEVICE_LABEL=iphone_16_pro_max_profile_usb
```

**Ricostruire prima:** `build/ios/iphoneos/Runner.app` e la QA installata sul
telefono precedono Source wrapper/tick stats. Al checkpoint la sessione Flutter
è stata chiusa con `q`, il telefono ha l'app QA installata ma chiusa; nessun
collector/Flutter run è attivo. L'app normale va ripristinata al termine.

Per cold successivi della stessa build, il launcher Flutter con
`--use-application-binary=build/ios/iphoneos/Runner.app` ha funzionato (~18 s).
CoreDevice launch + attach non dava VM raggiungibile: non ripetere quel loop.
Non salvare URL VM con token nei documenti/log di handoff.

Le viste QA disponibili sono `writer`, `song`, `fretboard`, `piano`, `minimal`.
Usare la vista Writer reale per la baseline; `WRITER_PROFILE_DURATION_SECONDS=60`
per le fixture prolungate. Il fixture harness usa repository temporanei e
directory QA uniche nell'app Caches. Non disinstallare l'app o cancellare dati
utente per ottenere un cold start.

## Sequenza successiva e criteri già approvati

1. Riparare/revisionare il parser e ricostruire la QA con l'ultima diagnostica.
   Verificare una cattura completa con Source e identity prima del lotto di test.
2. Per ciascuna fixture `plain_harmony`, `piano_harmony`, `six_note_strum`,
   `melody`, `recorded_clip` a 120 BPM: 10 cold + 10 warm di 8 battute e due
   playback di 60 s. Cold = processo nuovo e cache in memoria vuota, mai dati
   utente cancellati. Warm = stesso processo, attesa del fence/drain (~2 s).
   Comparare Song equivalente e audition Fretboard/Piano; includere confronto
   debug, senza assumere quale fosse la build originaria. Non ripetere 120 BPM
   come secondo tempo identico.
3. Ogni risultato richiede raw begin/end, conti attesi, manifest e finestra frame
   completa con `run_tag`/`profile_run_id` concordi; gli ID si ripetono tra processi.
   Il marker frame Writer attesta identity, non timestamp dell'input Play.
4. Review baseline fresh Sol prima di scegliere il fix. Ipotizzare preparazione
   limitata ai toni richiesti solo se le misure dimostrano source binding dominante.
   Backend nativo richiede evidenza e addendum concreto separato, revisionato.
5. Implementazione e review fresh Luna fino a PASS; misure matched prima/dopo,
   test di lifecycle e ascolto fisico prima di dichiarare risolto.

| Metrica | Gate |
| --- | --- |
| Entrata metodo transport → primo play/clip-resume Future completato | ≤2 s cold, ≤1 s warm |
| Lateness dispatch eventi | p95 ≤10 ms, worst ≤25 ms |
| Lateness Future delle voci preparate | p95 ≤30 ms, worst ≤60 ms |
| Errore offset di lancio Strum | p95 ≤10 ms, worst ≤25 ms; ordine preservato |
| Drift firmato first→last tick | ≤25 ms di variazione accumulata |
| Drop/duplicati/steal voci sostenute | 0 |
| Costo frame build/raster, target 120 Hz = 8,333 ms | p95 entro budget, exceedance ≤1%, worst ≤3 budget |

Source binding comprende native setSource, attesa prepared e position update
atteso. Source end→play end è **post-source play completion**, incluso resume e
bookkeeping Dart, non un resume RPC isolato. Future completato non prova onset
udibile. Ordine delle Future non prova ordine udibile delle note.

Per 60 s l'ultimo tick previsto è a 59,875 s: riportare primo/ultimo errore firmato
e differenza (`first_tick_dispatch_error_us`, `last_tick_dispatch_error_us`,
`tick_dispatch_error_change_us`) separatamente da completamento vs fine score.
Il normale completamento ~−123 ms rispetto a 60 s non è una misura di drift.
Non inferire cadenza display dividendo il numero di frame per il tempo.

`audioplayers` 6.6.0 / `audioplayers_darwin` 6.4.0: il percorso `play` attende
setSource (native prepared + position update), poi resume. WAV caldo non equivale
a AVPlayerItem preparato. Plain Harmony usa il pool preview condiviso da 6 voci;
Strum/Melody hanno il pool sequenced; clip registrati hanno un sink separato.
Il polling della posizione ogni frame è un'ipotesi da misurare, non una causa
accertata o un'autorizzazione a disabilitarlo.

La preparazione eventualmente introdotta deve acquisire ownership prima del
primo await, rendere Start idempotente e Stop disponibile, invalidare subito su
stop/progetto/dispose, e impedire che completamenti/cleanup vecchi modifichino
player o clip del run nuovo. Conservare volume, pan, durata, overlap, offset,
cache limitate e audition concorrente. Nessuna modifica a dipendenze/signing è
stata necessaria per questo checkpoint.
