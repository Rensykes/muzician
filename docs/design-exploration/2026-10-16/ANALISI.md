# Muzician — analisi di Fretboard, Piano e Writer

Studio del 16–17 ottobre 2026. Stato: analisi dell'app esistente e proposte di redesign, non specifica approvata né funzionalità implementate.

## Risultato dell'esplorazione

Muzician collega l'esplorazione musicale alla scrittura: Fretboard e Piano servono a trovare note, accordi e disposizioni; Writer li colloca in sezioni con testo e accompagnamento. Il Save System è il collegamento fra questi ambienti. Song è un arrangiatore distinto, raggiungibile tramite un'importazione dal Writer.

Il redesign dovrebbe rendere evidente questa continuità. Oggi le capacità sono ampie, ma molte sono distribuite fra icone, pannelli sovrapposti, menu di blocco e salvataggi con significati diversi. Il problema principale è la gerarchia delle azioni, non la mancanza di funzionalità.

Riferimenti di prodotto e stile consultati: [PRODUCT.md](../../../PRODUCT.md), [DESIGN.md](../../../DESIGN.md). Le cinque alternative esplorano nuove soluzioni senza sostituire questi riferimenti né cambiare l'app.

## Metodo e limiti

App avviata nel simulatore iPhone 18 Pro / iOS 27, build debug. La configurazione locale di Xcode richiedeva l'uso esplicito del Developer Directory; l'avvio è riuscito senza introdurre fix al codice applicativo. L'analisi statica svolta nella sessione è risultata pulita. Le modifiche iOS già presenti dell'utente sono state conservate.

Esplorazione effettuata nel progetto separato **Redesign study**, tonalità C major, 120 BPM. Stato osservato alla ripresa: sezione di otto battute, C–G–Dm–Dm, Harmony Fretboard, Guitar Strum non assegnato e lane audio vuota. Fretboard era configurata D Standard, capo 4. Non è stato sostituito questo contenuto per adattarlo ai mockup.

| Ambito | Verifica dal vivo | Verifica nel codice |
| --- | --- | --- |
| Fretboard | Note, modalità, riconoscimento, picker voicing, scale, accordatura/capo, salvataggi e trasferimento | Regole delle posizioni, filtri, ammissibilità Harmony, stato condiviso |
| Piano | Tastiera, C4/E4/G4, riconoscimento, inversioni, ottava, range, salvataggi, scelta del trasferimento | MIDI, vincoli del picker, selezione/focus e persistenza |
| Writer | Griglia popolata, menu del blocco, ruota accordi e picker esteso, mixer, strumming, menu generale, browser versioni, landscape | Sezioni, lane, riuso, audio, melodie, cronologia e importazione verso Song |
| Audio e conversioni | Non eseguita una prova completa di registrazione, import o qualità sonora | Letti flussi, editor e regole; non equivalgono a un collaudo end-to-end |

Sono incluse [15 catture reali](screenshots/). Il layout Writer è stato osservato sia a 402×874 punti sia a 874×402. Non sono stati collaudati VoiceOver, Dynamic Type, dispositivi fisici o tutte le combinazioni di accordature.

## 1. Struttura comune

La navigazione globale contiene sei destinazioni: Fretboard, Piano, Roll, Song, Writer, Settings. Un IndexedStack conserva le schermate. Fretboard e Piano condividono una struttura con intestazione/progetto, superficie strumentale, risultati del riconoscimento e dock Scale/Chord; le impostazioni dello strumento e la libreria si aprono in pannelli.

I pannelli comuni sono bottom sheet modali con contenuto scorrevole, altezza massima circa 85%, maniglia e chiusura. La maniglia non implica un vero pannello trascinabile fra più altezze: il codice non usa DraggableScrollableSheet. Questa distinzione conta per il redesign.

Il progetto conserva tonalità, tempo e metro. Un cambio della tonalità dagli strumenti o dal Writer richiede conferma e aggiorna il contesto comune. Caricare un Save strumentale non deve sovrascriverla. Sharps/Flats cambia la visualizzazione dei nomi, non le altezze musicali né i nomi assegnati dall'utente.

Fonti: [main.dart](../../../lib/main.dart) (navigazione e composizione delle schermate), [InstrumentScreen](../../../lib/features/instrument_shared/instrument_screen.dart), [shell/pannelli](../../../lib/features/_mockup_shell.dart), [sincronizzazione progetto](../../../lib/store/project_config_sync.dart).

## 2. Fretboard

### Superficie e selezione

Il manico è una superficie orizzontale scorrevole con sei corde, tasti, note e marcatori. Mantiene dimensioni fisiche relativamente stabili: non comprime tutta la tastiera per farla entrare nello schermo. La configurazione predefinita nel codice è 12 tasti, EADGBE, capo 0, modalità Free ed Exact. Il renderer distingue tap e trascinamento; non implementa pinch-to-zoom.

**Free** consente esplorazione libera. **Chord** limita la selezione a una posizione per corda e abilita, con una selezione valida, il trasferimento Harmony. Cambiare modalità non deve essere interpretato come una conversione automatica di ogni idea Free in accordo valido. Una selezione Free rimane un'idea strumentale salvabile, ma non entra nel Writer.

Il pannello di riconoscimento mostra note selezionate, accordi candidati e scale compatibili. Il focus su una nota opera sulla classe di altezza; un accordo candidato apre le disposizioni. L'azione Clear del pannello riguarda selezione/focus; Clear all nelle impostazioni ha portata più ampia. Non vanno presentate come sinonimi.

### Pannelli aperti e contenuto

- **Chord:** fondamentale, qualità e fino a 24 diagrammi, calcolati rispetto ad accordatura e capo. Il diagramma scelto viene applicato senza chiudere il pannello. Il bordo selezionato è un feedback essenziale da mantenere.
- **Scale:** fondamentale e famiglie Common, Modes, Extended. Include major/minor, pentatoniche e blues; modi; harmonic/melodic minor, whole tone e diminished. La scala selezionata guida gli highlight e, nel progetto, il cambio della tonalità confermata.
- **Settings:** Exact/Solo, Clear all, accordature raggruppate Standard/Metal/Midwest Emo, capo 0–11. Solo riduce il rumore nascondendo note estranee al contesto. Le dieci accordature comprendono Standard, Drop D, Eb Standard, D Standard, Drop C, Drop B, Open D, Open G, DADGAD, FACGCE.
- **Saves:** navigazione delle cartelle del progetto, salvataggio dell'idea, caricamento e riuso. Non è la stessa operazione che salvare una versione del Writer.

Il capo riposiziona la forma e può eliminare posizioni fuori intervallo. È un parametro musicale, non un semplice filtro grafico. Il numero dei tasti è regolabile nelle API (1–24), ma non emerge come controllo nella schermata analizzata: non va aggiunto ai mockup come se fosse già presente.

Evidenze: [voicing](screenshots/01-fretboard-chord-voicings.png), [detection](screenshots/02-fretboard-detection.png), [impostazioni](screenshots/10-fretboard-settings.png). Codice: [renderer](../../../lib/features/fretboard/fretboard.dart), [picker](../../../lib/features/fretboard/chord_voicing_picker.dart), [capo](../../../lib/features/fretboard/capo_control.dart), [store](../../../lib/store/fretboard_store.dart).

## 3. Piano

Il Piano usa note MIDI esatte, quindi distingue le ottave. Un tap seleziona/deseleziona e produce l'audizione. La tastiera scorre orizzontalmente; il codice usa Stack/Positioned e GestureDetector, non un CustomPainter. Non è implementato un glissando continuo.

La tastiera ha dimensioni dei tasti relativamente stabili. Le impostazioni offrono 49 tasti C2–C6, 61 C2–C7 (default), 88 A0–C8. Il range deve restare accessibile senza trasformare il piano in una miniatura non suonabile.

Il picker Chord ha fondamentale/qualità come Fretboard, ma controlli specifici: ottava da 1 a 7 e fino a tre disposizioni, Root, 1st inversion, 2nd inversion. Non è corretto copiare semplicemente i diagrammi della chitarra. Il generatore richiede almeno tre note: la qualità 5th non produce queste carte di inversione, un caso limite da gestire esplicitamente in un futuro intervento.

Il riconoscimento parte da almeno due classi di altezza distinte e usa le informazioni MIDI per il basso degli slash chord. I chip delle note danno focus; accordi e scale offrono azioni contestuali. Il pannello osservato con C4/E4/G4 riconosce C. Le impostazioni riprendono Exact/Solo e Clear all.

Evidenze: [inversioni](screenshots/05-piano-voicings.png), [riconoscimento](screenshots/06-piano-detection.png), [range](screenshots/07-piano-settings.png), [libreria](screenshots/08-piano-saves.png). Codice: [keyboard](../../../lib/features/piano/piano_keyboard.dart), [picker](../../../lib/features/piano/piano_chord_picker.dart), [detection condivisa](../../../lib/features/instrument_shared/shared_detection_panel.dart).

## 4. Dallo strumento al Writer

Il dialogo **Add to Writer** distingue due percorsi reali:

1. **Accordo riconosciuto:** trasferisce identità armonica e strumento. Non va promesso che conservi automaticamente l'esatta disposizione fisica selezionata.
2. **Exact Harmony:** conserva note MIDI o posizioni native e un nome scelto dall'utente. Non inventa fondamentale, qualità o grado romano se non esiste un'identità armonica.

Seguono scelta della sezione, lane compatibile e battuta; un nuovo contenuto riceve un nome e un Save. Se manca una sezione, il flusso può proporne una di otto battute. Il trasferimento richiede un progetto reale, non Dump. Una destinazione già occupata comporta sostituzione esplicita; cambiare progetto o selezione durante il flusso può annullarlo.

Per Fretboard servono modalità Chord e posizioni valide, una per corda. Piano richiede MIDI validi e unici nel range. Il pulsante disabilitato deve spiegare il requisito senza costringere l'utente a dedurlo dal colore.

C'è una differenza importante fra operazioni fuori tonalità: un tap manuale può offrire Stay in project / Switch to Dump; applicare un voicing fuori tonalità può offrire Apply anyway restando nel progetto. Un redesign non dovrebbe nascondere questa differenza dietro un unico comando ambiguo; armonizzarla richiederebbe una decisione sul comportamento.

Evidenza: [scelta di trasferimento](screenshots/09-piano-writer-handoff.png). Fonti: [writer_handoff.dart](../../../lib/features/instrument_shared/writer_handoff.dart), [songwriter_rules.dart](../../../lib/schema/rules/songwriter_rules.dart).

## 5. Writer

### Modello e struttura

La gerarchia è **progetto → sezioni → lane → blocchi posizionati in battute**. Una sezione ha nome, lunghezza e ripetizioni. La stessa musica ripetuta può avere testi diversi per strofa. La testata ospita progetto, indicatore di modifiche, salvataggio, guida e menu; il trasporto raccoglie tonalità, BPM, play e metronomo. Il selettore diretto della tonalità propone major/minor, mentre il modello può ricevere altri modi dagli strumenti. Il tempo selezionabile è 40–240 BPM.

La sezione mostra righello, numero di battute, ripetizioni, mixer, azioni e rimozione con recupero tramite undo. Il righello permette di scegliere il punto di partenza. La griglia Harmony si dispone in quattro celle per riga, con simbolo, grado, testo e riferimenti ai Save.

In landscape la testata superiore scompare quando l'altezza è ridotta e guida/menu si spostano nel trasporto. Il corpo può usare due colonne da 700 punti di larghezza: nella cattura con una sola sezione occupa la colonna sinistra, lasciando spazio vuoto a destra. Il semplice aumento della larghezza non garantisce un uso efficace dello spazio.

### Harmony e menu dei blocchi

Ogni lane Harmony è associata a Piano o Fretboard. Su una battuta vuota si apre prima un menu (Play from here, Add chord, Add from library); la ruota non appare direttamente al primo tap.

Con una scala a sette gradi, Add/Change chord può mostrare la ruota diatonica e Other chord. Quest'ultimo apre fondamentale/qualità. Una scala non compatibile usa il picker diretto. Esiste anche un segnaposto silenzioso per testo senza accordo nella lane primaria.

Il menu del blocco include riproduzione, Change/Replace chord, voicing/libreria, modifica nello strumento, testo, rinomina, copia autonoma e rimozione. Sono operazioni diverse: cambiare il contenuto condiviso e sostituire quel singolo posizionamento non devono sembrare la stessa azione. I blocchi Exact conservano il nome e omettono i controlli teorici non applicabili.

### Lane e pannelli secondari

| Lane/funzione | Comportamento verificato nel codice | Implicazione di design |
| --- | --- | --- |
| Harmony e Save/voicing | Accordi legati allo strumento e realizzazioni native; alcuni Save sono visualizzati ancorati ad Harmony | Mostrare origine, riuso e stato della selezione |
| Guitar Strum | Pattern da 1/2/4 battute, passi in sedicesimi off/down/up; sorgente Harmony Fretboard esplicita | Fonte visibile; stato Unassigned comprensibile; gruppi ritmici di quattro |
| Drum | Pattern di sezione, editor a step, preset/My loops, fill/clear, accompagnamento | Editor contestuale senza coprire il riferimento ritmico |
| Melody | Piano Roll isolato con salvataggio esplicito, riuso, loop/troncamento e performance Piano/Fretboard | Distinguere modifica del pattern da modifica del posizionamento |
| Audio | Import WAV/MP3/M4A o registrazione; waveform, trim, slice/scatter, annotazioni accordi, fit/loop/one-shot/stretch | Non far sparire lo stato di registrazione o l'origine del clip |
| Lyrics | Testo dei blocchi nella lane primaria e testo libero per ripetizione | Chord e lyric devono essere leggibili insieme |

Uno stesso Harmony Fretboard può alimentare al massimo una lane Guitar Strum nella sezione. Una lane non assegnata è silenziosa. Nel pannello reale i 16 passi occupano righe da 7+7+2: è un problema di lettura ritmica, anche se le azioni sono disponibili.

Il mixer di sezione offre nome, mute, volume e pan; i voicing ereditano Harmony. La cronologia è in memoria, limitata a 50 snapshot precedenti e separata per progetto. Cambio progetto, New e caricamento di una versione nominata la azzerano: non è una cronologia permanente.

Menu globale: New project, Undo, Redo, Save, Browse saves, Edit structure, Rename project. New project protegge il lavoro corrente con Keep/Discard/Cancel. Edit structure riordina le sezioni.

Evidenze: [sezione](screenshots/11-writer-section.png), [ruota](screenshots/03-writer-chord-wheel.png), [mixer](screenshots/04-writer-mixer.png), [strumming](screenshots/12-writer-strum.png), [menu](screenshots/13-writer-menu.png), [landscape](screenshots/15-writer-landscape.png).

Fonti: [screen sheet](../../../lib/features/songwriter/songwriter_screen_sheet.dart), [header](../../../lib/features/songwriter/songwriter_header.dart), [mixer](../../../lib/features/songwriter/songwriter_mixer_sheet.dart), [melody editor](../../../lib/features/songwriter/songwriter_melody_pattern_editor.dart), [audio clip](../../../lib/features/songwriter/songwriter_audio_clip_sheet.dart), [playback](../../../lib/store/songwriter_playback_store.dart).

## 6. Salvataggi, riuso e Song

Tre concetti devono essere distinguibili:

- **Bozza corrente:** Writer viene persistito per progetto. Unsaved indica una differenza rispetto alla versione nominata associata, non necessariamente perdita del lavoro chiudendo l'app.
- **Idea / Harmony Save:** contenuto musicale riutilizzabile con identità stabile. Il blocco Writer mantiene posizione e testo locale; la musica canonica risiede nel Save System, con fallback per recupero.
- **Versione del Writer:** snapshot nominato, visibile in Browse saves → Song versions. Non equivale a un salvataggio del workspace Song. Il pannello separa Song versions e Section blocks.

Modificare un Save condiviso può aggiornare tutti i suoi utilizzi oppure creare un Save autonomo. Creare una copia non significa automaticamente sostituire il blocco corrente: Replace chord è un passaggio distinto. Il caricamento storico materializza il contenuto della versione senza sovrascrivere indiscriminatamente i contenuti canonici correnti. Le versioni possono essere esplicitamente sovrascritte: non sono immutabili in senso assoluto.

**Song → More → Import from Writer** converte una fotografia del Writer in arrangiamento: sezioni e ripetizioni diventano timeline/marker; Harmony, voicing, melodie e strum diventano note, drum diventa batteria. Non è un collegamento live. L'audio Writer è escluso. Sostituire un arrangiamento significativo richiede conferma ed è una transazione recuperabile con undo.

Evidenze: [versioni](screenshots/14-writer-versions.png). Fonti: [save panel](../../../lib/features/songwriter/songwriter_save_panel.dart), [save model](../../../lib/models/save_system.dart), [Writer store](../../../lib/store/songwriter_store.dart), [conversione Song](../../../lib/schema/rules/song_from_writer_rules.dart), [guida Save System](../../../docs/save_system.md).

## 7. Problemi osservati e priorità

| Priorità | Evidenza | Direzione proposta |
| --- | --- | --- |
| Alta | Titoli Fretboard/Piano troncati con il nome progetto lungo | Separare contesto progetto e titolo; dare priorità al workspace |
| Alta | Save idea, Add to Writer e Save version distribuiti in punti diversi | Etichette esplicite e percorso selezione → riuso → collocazione |
| Alta | Pattern strum 7+7+2 | Quattro gruppi di quattro passi, con beat e stato testuale |
| Alta | Tante azioni equivalenti nel menu del blocco | Azioni frequenti visibili; avanzate raggruppate per conseguenza |
| Media | Grande spazio vuoto nella detection iniziale; due righe di navigazione | Stato iniziale utile e pannello contestuale compatto |
| Media | Impostazioni con RANGE duplicato e CAPO spezzato | Etichette uniche, controlli con larghezza minima e reflow |
| Media | Capo e ottava con controlli visivamente piccoli | Target almeno 44×44; verificare hit area e testo ingrandito |
| Media | Strum ripetuto consuma molto spazio verticale | Riepilogo del pattern e indicazione della durata, espansione su richiesta |
| Media | Landscape con sola sezione lascia mezza area inutilizzata | Struttura + editor/inspector, preservando il contesto musicale |

La verifica dell'albero accessibile non ha restituito dettagli sufficienti sul contenuto Flutter nella seconda parte della sessione. Le osservazioni visuali non attestano conformità VoiceOver/WCAG. Nel prototipo successivo andranno controllati semantics, ordine di lettura, contrasto misurato e Dynamic Type.

## 8. Divergenze fra guide e implementazione

Le guide esistenti non sono state riscritte durante questo studio, perché non si è modificato il prodotto. Per interpretare l'app si è usato il codice corrente:

- `docs/fretboard.md` contiene riferimenti a default di 15 tasti e descrizioni/preset non allineati; il codice usa 12 tasti e le dieci accordature descritte sopra.
- `docs/piano.md` descrive un default di 49 tasti e un range non corrispondente; quello corrente è 61, C2–C7. CustomPainter, adattamento totale alla viewport e glissando non descrivono il renderer attuale.
- Nomi di vecchi screen mockup/pannelli separati e controlli Load/Highlight non corrispondono all'interfaccia visitata. La coppia attuale è Exact/Solo.
- Alcune descrizioni del Writer fanno pensare a una ruota immediata sulla cella vuota; c'è invece un menu intermedio. Il selettore major/minor non esaurisce le tonalità supportate dal modello.

Un futuro redesign implementato dovrà riconciliare queste guide, aggiornare PRODUCT/DESIGN e verificare le feature interessate. Queste note non autorizzano a eliminare funzionalità perché assenti da una vecchia guida.

## 9. Vincoli per i cinque mockup

Ogni alternativa contiene tre schermate coerenti: Fretboard, Piano, Writer. La lingua dell'interfaccia rimane inglese per confronto con l'app corrente. Il contenuto dimostrativo è normalizzato: progetto Redesign study, C major, 120 BPM; selezione C; Writer con C–G–Dm–Dm e otto battute. Nei mockup Fretboard usa Standard/capo 0 per rendere leggibile il diagramma: è uno stato illustrativo, non una modifica al progetto reale.

Invarianti: modalità Free/Chord; tuning/capo; piano range/ottava/inversioni; distinzione accordo/Exact Harmony; tonalità del progetto condivisa; sei destinazioni accessibili; idea distinta dalla versione; fonte esplicita dello strum; undo; posizione e testo separati dal contenuto musicale condiviso. I pannelli mostrati aperti non devono coprire completamente lo strumento o la sezione.

I mockup sono immagini concettuali, non schermate funzionanti. Nuovi raggruppamenti, etichette e pannelli persistenti sono proposte. Le immagini non sostituiscono la validazione del motore musicale: geometria, spelling, voicing, contrasto e dimensioni dei target vanno verificati nel prototipo Flutter.

Le cinque direzioni, con vantaggi e compromessi, sono in [DIREZIONI.md](DIREZIONI.md). I prompt completi usati per generare le tavole sono in [PROMPTS.md](PROMPTS.md).
