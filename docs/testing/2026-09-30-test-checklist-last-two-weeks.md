---
title: "Muzician — checklist test change ultime due settimane"
created: 2026-09-30
period: 2026-09-16/2026-09-30
status: da-testare
tags:
  - muzician
  - qa
  - ios
  - manual-test
---

# Checklist test — change dal 16 al 30 settembre 2026

> [!info] Perimetro
> Nel periodo ci sono cinque commit applicativi, dal 24 al 29 settembre: `8ec9f20`, `136d87d`, `0dc509f`, `70384c2` e `b5e7812`. Questa checklist raccoglie le verifiche manuali sul dispositivo; test automatici e controlli già riportati nei piani di implementazione non sono ripetuti come risultati di questa sessione.

> [!warning] Dati di prova
> Usa un progetto dedicato, ad esempio `QA iPhone 2026-09-30`, e contenuti sacrificabili. Non usare **Start fresh**, cancellazioni o import con sostituzione sui dati personali. Le prove che richiedono JSON malformato vanno fatte solo con un payload fixture e un'installazione/profilo QA dedicato.

## 0. Avvio su iPhone

- [ ] Collega e sblocca l'iPhone; conferma che questo Mac è attendibile e che Developer Mode è attivo.
- [ ] In Xcode → Settings → Accounts, configura l'account Apple per development e verifica che Automatic Signing possa creare un provisioning profile per Muzician.
- [ ] In Codex, apri l'ambiente **Muzician iOS** e avvia l'azione **Deploy to iPhone**.
- [ ] Verifica che l'azione selezioni l'iPhone fisico, costruisca la versione Release firmata, la installi e apra Muzician oltre lo splash screen.
- [ ] Scollega il cavo dopo l'apertura; verifica che l'app resti utilizzabile senza Flutter o il Mac collegato.
- [ ] Se sono collegati più iPhone, imposta `MUZICIAN_IOS_DEVICE_ID` con l'ID mostrato da `flutter devices`; verifica che venga usato quel dispositivo.
- [ ] Scollega l'iPhone e rilancia l'azione: deve spiegare che non trova un dispositivo fisico, senza avviare per errore il simulatore.
- [ ] Ricollega il telefono e verifica che il rilancio riparta senza cambiare il progetto QA.

## 1. Avvio, navigazione e recupero dati — `8ec9f20`

Riferimenti: [[song_writer_guide]], [[save_system]], [[2026-09-24-songwriting-workflow-improvement]].

### Avvio e workspace ricordato

- [ ] Al primo avvio QA, verifica che venga aperto Writer e che la schermata di caricamento preceda i workspace.
- [ ] Passa da Writer a Fretboard, Piano, Piano Roll, Song e poi Settings; riavvia l'app e verifica che venga ripristinato l'ultimo workspace di contenuto.
- [ ] Visita Settings come ultima schermata, riavvia e verifica che Settings non venga ricordato al posto dell'ultimo workspace di contenuto.
- [ ] Durante il primo caricamento, verifica che non si possa modificare un workspace prima che sessione e Save System siano idratati.
- [ ] Cambia progetto, riavvia e verifica che il contenuto mostrato appartenga al progetto selezionato e che le modifiche dell'altro progetto restino isolate.

### Handoff Fretboard/Piano → Writer

- [ ] Su Fretboard, seleziona una forma esatta e usa l'azione per inserirla in Writer: scegli sezione e battuta; verifica che venga creato un blocco Save con la forma e posizione corrette, senza richiedere prima un salvataggio nella libreria.
- [ ] Su Fretboard, trasferisci un accordo rilevato: verifica che il blocco Harmony conservi simbolo, fondamentale, qualità e note selezionate.
- [ ] Ripeti i due trasferimenti da Piano, verificando note e ottava della selezione nativa.
- [ ] Con Writer senza progetto, avvia un handoff e annulla il selettore progetto: verifica che Writer e strumento restino invariati.
- [ ] Con Writer senza sezioni, avvia un handoff e scegli di creare la sezione iniziale; verifica che il trasferimento finisca nella battuta scelta.
- [ ] Prova una battuta occupata: confronta sostituzione, scelta di un'altra battuta e annullamento. Annullare deve lasciare il contenuto invariato.
- [ ] Con un blocco ripetuto, sostituisci una delle sue occorrenze: verifica che cambi il blocco sorgente e che tutte le occorrenze ripetute mostrino lo stesso nuovo contenuto, mantenendo posizione e durata.
- [ ] Cambia progetto mentre il selettore di destinazione è aperto: il trasferimento deve essere annullato e non deve finire nel nuovo progetto per errore.

### Recupero e persistenza

- [ ] Con il progetto QA, crea contenuti in Writer, Song e Save System, chiudi e riapri l'app; verifica il ripristino dei dati.
- [ ] Con un fixture QA malformato per sessione o Save System, verifica che l'app offra Retry/Recovery senza sovrascrivere i byte originali prima della scelta esplicita.
- [ ] Nel flusso QA di avvio pulito, verifica che il payload originale sia copiato nei dati di recupero prima di inizializzare dati nuovi.
- [ ] In Settings → Data Recovery, copia ed esporta una voce e confronta il contenuto esportato con il payload originale; elimina una sola voce con conferma e verifica che le altre restino.
- [ ] Simula un errore di lettura solo nell'ambiente QA: verifica Retry e che nessun workspace modificabile venga aperto finché l'idratazione non riesce.

## 2. Empty state Song e import contestuale da Writer — `136d87d`

Riferimenti: [[song_workspace]], [[song_writer_guide]].

- [ ] Con Song vuoto e Writer senza contenuti trasferibili, verifica lo stato **No tracks yet** e l'azione **Add Track**; non deve apparire un invito all'import vuoto.
- [ ] Con Writer che contiene accordi, voicing, drum, melody o strum, verifica che Song vuoto mostri **Import from Writer** e descriva il trasferimento.
- [ ] Con Writer che contiene solo audio lane, verifica che non venga proposta un'importazione senza tracce trasferibili; l'audio Writer resta escluso.
- [ ] Verifica che **Add Track** rimanga disponibile anche quando compare il pulsante di import Writer.
- [ ] Crea un progetto con tempo, metrica e tonalità definiti; verifica che il Song iniziale erediti quei valori e non chieda una conferma di sostituzione senza contenuti modificati.
- [ ] Modifica in Song solo tempo, metrica o tonalità, lasciando la timeline vuota; scegli **Import from Writer** e annulla la conferma: i valori Song devono restare invariati.
- [ ] Ripeti e conferma l'import: Song deve adottare configurazione e contenuti derivati dal Writer del progetto attivo.
- [ ] Ridimensiona la viewport del contenuto vuoto: lo stato onboarding deve poter scorrere e i controlli non devono andare fuori schermo.

## 3. Song, registrazione, export e undo — `8ec9f20`

Riferimenti: [[song_workspace]], [[song_writer_guide]], [[2026-09-24-songwriting-workflow-improvement]].

### Riproduzione dopo l'import Writer → Song

- [ ] Con Writer valorizzato e Song vuoto, verifica che l'azione di import sia visibile e spieghi cosa verrà trasferito.
- [ ] Importa un progetto QA con più sezioni: verifica misure e marker, tempo, metrica e tonalità.
- [ ] Verifica che gli accordi Harmony e le forme salvate diventino tracce di note; melody diventi traccia note; Guitar Strum diventi eventi di note; drum lane diventi traccia drum.
- [ ] Verifica che le audio lane Writer restino in Writer, non vengano importate in Song e che il messaggio lo dichiari chiaramente.
- [ ] Riproduci Writer e Song dopo l'import e confronta inizio, durata, ripetizioni e fine degli eventi, inclusi pattern ripetuti e strum.
- [ ] Verifica che l'import contestuale non venga offerto quando non ci sono tracce trasferibili o quando Song contiene già materiale.

### Registrazione Song e WAV

- [ ] Avvia una registrazione Song e fermala: verifica che il take apra prima una schermata di revisione e che non venga committato automaticamente.
- [ ] Riascolta il take, scarta/annulla la revisione e verifica che non compaia una clip; ripeti e conferma per creare la clip.
- [ ] Registra o importa una clip e prova trim, posizione temporale, gain, mute e solo; ascolta il mix e verifica che ogni controllo abbia effetto.
- [ ] Esporta un WAV PCM16 da Song con note, drum e clip audio: verifica che la clip sia inclusa, che trim e start time siano rispettati e che mute/solo/gain siano applicati.
- [ ] Sul WAV esportato, controlla durata, canali e apertura nell'app File o in un player iOS compatibile.
- [ ] Prova una clip in formato/codec non supportato dal mixdown: il preflight deve spiegare il problema e non deve generare un WAV incompleto.
- [ ] Verifica che esportazione WAV e backup di recupero presentino il pannello iOS di condivisione/salvataggio; annullare il pannello non deve mostrare un messaggio di esportazione riuscita.

### Song Bundle e storia

- [ ] Esporta un Song Bundle che contiene clip audio; verifica che il file sia condivisibile e che il bundle includa audio sorgente e arrangiamento.
- [ ] In un progetto QA vuoto, importa il bundle ed esamina marker, tracce, clip e riproduzione.
- [ ] In un Song QA non vuoto, avvia l'import: annulla la conferma di sostituzione e verifica che il Song originale resti intatto.
- [ ] Conferma la sostituzione; usa Undo e Redo e verifica che arrangiamento e riferimenti ai file audio tornino insieme, senza clip orfane.
- [ ] In Writer e Song, prova una modifica singola, Undo e Redo; poi cambia progetto e verifica che la storia del progetto precedente non agisca sul nuovo.
- [ ] In Writer, prova New e caricamento di un named Save: verifica che la cronologia venga azzerata sui confini previsti.
- [ ] Accumula più modifiche nel progetto QA e verifica Undo ripetuto e Redo ripetuto, inclusi azioni composte come eliminazione e import.

## 4. Writer e Save System collegati — `0dc509f`

Riferimenti: [[songwriter]], [[save_system]], [[2026-09-27-writer-save-structure]].

- [ ] Crea una sezione Writer e verifica che compaiano le cartelle/categorie Save previste per la sezione e che siano distinte per Harmony e contenuti strumentali.
- [ ] Salva un blocco Writer e verifica che il contenuto musicale canonico sia nell'entry Save System, mentre Writer conservi collocazione e testo locale.
- [ ] Modifica e riapri il blocco collegato: verifica che l'entry canonica e i suoi collegamenti restino coerenti.
- [ ] Usa lo stesso Save in più blocchi; scegli l'aggiornamento condiviso e verifica che ogni uso rifletta il cambiamento.
- [ ] Ripeti scegliendo una copia/Save indipendente; verifica che l'entry originale e gli altri blocchi non cambino.
- [ ] Sposta o riordina blocchi e cartelle, chiudi e riapri l'app; verifica che collegamenti, categoria e posizione persistano.
- [ ] Annulla e ripeti una modifica composta Writer + Save System; verifica che Writer e Save System non restino in stati discordanti.
- [ ] Elimina e annulla l'eliminazione di una sezione/cartella QA con contenuti: verifica la gestione dei discendenti e la ricollocazione dei Save appartenenti a Writer.

## 5. Harmony lane per strumento e Save compositi — `70384c2`

Riferimenti: [[songwriter]], [[save_system]], [[2026-09-28-writer-harmony-instrument-lanes]].

### Strumento per progetto e lane

- [ ] Imposta il default globale Harmony su Piano; crea un progetto normale e verifica che nuovo progetto e prima Harmony lane seguano il default.
- [ ] Cambia il default globale su Fretboard e crea un altro progetto; verifica che non si modifichi retroattivamente il primo progetto.
- [ ] In Writer, crea un nuovo progetto: scegli Piano o Fretboard e verifica che la scelta valga per quel progetto senza cambiare il default globale.
- [ ] In un progetto con Harmony Piano, aggiungi una Harmony lane Fretboard (e viceversa); verifica che lane, intestazione e azioni mostrino lo strumento della lane.
- [ ] Aggiungi una seconda lane dello stesso tipo; verifica che i controlli e i blocchi restino associati alla lane corretta.

### Accordi e Save compositi

- [ ] Aggiungi un accordo a una Harmony Piano lane: verifica accordo musicale e voicing Piano nello stesso Save composito.
- [ ] Ripeti su Harmony Fretboard: verifica che il voicing sia suonabile con tuning/capo correnti; prova una qualità di accordo e una posizione non disponibile.
- [ ] Usa una Harmony chord Save dalla libreria in una lane compatibile: verifica che riusi la stessa entry e crei un blocco Harmony, non un blocco Save strumentale.
- [ ] Prova a usare/editare un Save su una lane di strumento incompatibile: la UI deve impedirlo o offrire una risoluzione esplicita senza mutare il contenuto.
- [ ] Modifica il native voicing da Piano/Fretboard e scegli aggiornamento di tutti gli usi: riapri i blocchi collegati e verifica il nuovo voicing.
- [ ] Ripeti scegliendo un Save indipendente; verifica che gli altri usi restino invariati.
- [ ] Sostituisci l'accordo di un singolo blocco Harmony: verifica che posizione, durata e testo/lyrics locali restino uguali.
- [ ] Duplica una Harmony lane e verifica l'invariante di strumento e i collegamenti previsti.
- [ ] Elimina una Harmony lane usata da altri contenuti, poi annulla: verifica che gli anchor e i blocchi dipendenti siano recuperabili e non si spostino su una lane diversa.
- [ ] Verifica la navigazione fra sezioni, cartelle di categoria e Save, compresi collegamenti dopo riapertura dell'app.

## 6. Guitar Strum, Melody e nuovo progetto Writer — `b5e7812`

Riferimenti: [[songwriter]], [[song_writer_guide]], [[2026-09-29-writer-melody-strumming-project]].

### Guitar Strum

- [ ] In una sezione con solo Harmony Piano, verifica che non si possa aggiungere una Guitar Strum lane.
- [ ] Aggiungi una Harmony Fretboard lane e poi Guitar Strum: verifica che il selettore sorgente mostri solo Harmony lane Fretboard.
- [ ] Seleziona esplicitamente una lane Fretboard non primaria; verifica che l'anchor resti quella lane anche se cambia la primaria.
- [ ] Apri la tile del pattern: verifica anteprima ordinata degli eventi down/up e modifica pattern senza perdere assegnazione o durata.
- [ ] Cambia l'anchor e ascolta il playback: le note devono seguire l'accordo della sorgente selezionata.
- [ ] Trasforma la sorgente selezionata in Piano o rimuovila: lo strum deve risultare unresolved/silenzioso e riparabile; non deve passare automaticamente a un'altra Harmony lane.
- [ ] Ripara l'anchor verso un'altra lane Fretboard e verifica che il playback riprenda.
- [ ] Importa in Song due occorrenze strum su accordi diversi; verifica che ogni occorrenza usi le note del proprio accordo.

### Melody: durata, riuso e posizione esecutiva

- [ ] Crea una melodia dal Piano Roll e torna a Writer: verifica la durata esatta (barre e residuo musicale) e la finestra di collocazione nel blocco.
- [ ] Riusa lo stesso pattern in una seconda battuta; crea una sequenza A–B–A–B e verifica che A mantenga note e mappatura in entrambi gli usi.
- [ ] Cambia durata e collocazione del blocco: verifica ripetizione se il blocco supera la durata del pattern e clipping se è più corto.
- [ ] Prova una collocazione oltre la durata sezione e una che invade un blocco vicino; l'operazione non deve sovrapporre o perdere dati.
- [ ] Dividi un blocco multi-barra al confine della riga della griglia; verifica che i segmenti continui mostrino correttamente la stessa collocazione.
- [ ] Scegli Piano come strumento esecutivo e verifica ogni nota nel range corrente; scegli un range non compatibile e verifica il gate con spiegazione, senza aprire una vista impossibile.
- [ ] Scegli Fretboard e verifica per ogni nota stringa e tasto fisico; prova capo, accordatura alternativa e numero di tasti, includendo una nota non suonabile.
- [ ] Salva posizioni Fretboard, chiudi e riapri pattern/progetto; verifica che ogni nota conservi la stessa posizione.
- [ ] Modifica le note nel Piano Roll: verifica che le posizioni siano conservate per note invariate, riconciliate per note cambiate e rimosse per note cancellate.
- [ ] Suona una melodia e verifica che le durate delle note terminino entro pattern, blocco e sezione, anche ai bordi.

### Creazione progetto Writer e protezione sessione

- [ ] Avvia la creazione progetto Writer da una sessione vuota: verifica nome, scelta esplicita Piano/Fretboard e apertura del nuovo progetto con Writer vuoto.
- [ ] Modifica il Writer corrente e scegli Keep: apri di nuovo il progetto precedente e verifica che la sessione sia intatta.
- [ ] Modifica il Writer corrente e scegli Discard quando c'è un named Save attivo: verifica che venga ripristinato quel Save e che gli altri named Save restino.
- [ ] Ripeti Discard senza named Save collegato: verifica che sessione e binding del progetto corrente vengano puliti senza cancellare named Save.
- [ ] Scegli Cancel nella finestra Keep/Discard/Cancel: verifica che non venga creato un progetto né cambiato il progetto selezionato.
- [ ] Torna più volte fra due progetti e verifica che nome, configurazione Harmony, Writer e binding rimangano isolati.
- [ ] Dopo Keep e Discard, riavvia l'app: verifica che la scelta si sia salvata completamente e che non ricompaiano dati obsoleti.

## 7. Layout, accessibilità e regressioni trasversali

- [ ] In portrait sul telefono, verifica navigazione, titoli, toolbar, menu e dialoghi di Fretboard, Piano, Writer, Song e Save System senza overflow.
- [ ] Ruota in landscape; verifica Piano Roll, Song timeline, sezioni Writer, mixer e pannelli di salvataggio senza controlli tagliati.
- [ ] Verifica che selezione, unresolved, errore e stato disabled non siano comunicati solo con il colore.
- [ ] Verifica etichette accessibili per handoff, anchor, anteprima strum, import, export, Undo/Redo, Keep/Discard/Cancel e controlli di progetto.
- [ ] Verifica che i target touch principali siano comodi e che annullare dialoghi o sheet non lasci modifiche parziali.
- [ ] Esegui un giro completo sul progetto QA: idea/voicing → Writer → Save → Song → playback/export → Undo/Redo → riapertura.
- [ ] Registra qui eventuali esiti non passati, modello iPhone/iOS, build SHA e passaggi per riprodurli.

## Esiti

- Dispositivo / versione iOS:
- Build / commit:
- Data test:
- Problemi aperti:
- Note:

> [!info] Deploy standalone verificato il 30 settembre
> Il build Release è stato firmato, installato e lanciato su `iPhone di Francesco` (iOS 27.0). Il tentativo in debug si interrompeva perché `iproxy` richiede Rosetta su questo Mac; il percorso Release usa `devicectl` e non avvia il debugger Flutter. L'azione Codex ora segue il percorso Release.
