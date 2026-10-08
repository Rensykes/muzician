# Writer: Harmony non riconosciuta, Free, chiave e strumming

Stato: piano revisione 2 APPROVATO dalla review GPT-6.1 Sol extra high e
dall'utente. Implementazione e verifiche del 4 ottobre completate; review
indipendenti finali ancora da eseguire. Il 7 ottobre i subagent fresh sono di nuovo
disponibili, ma sono stati segnalati e riprodotti nuovi casi non coperti dal QA
precedente. Le correzioni e la review complessiva proseguono nel
[piano del 7 ottobre](2026-10-07-spelling-harmony-replacement-playback.md).

## Decisioni concordate

- Nella stessa sezione, una Harmony lane Fretboard può essere sorgente di una
  sola Guitar Strum lane. I target occupati da un'altra lane sono nascosti;
  la sorgente corrente della lane rimane selezionabile. Il limite riguarda
  le lane, non il riuso di uno stesso pattern in slot successivi.
- Piano e Fretboard in modalità Chord possono fornire Harmony anche quando
  l'app non riconosce un accordo. Si conservano nome scelto e note esatte,
  senza inventare tonica, qualità o numero romano. Questi blocchi hanno
  Change chord e Replace chord e compaiono nella Harmony Library del progetto
  per lo stesso strumento.
- Fretboard Free resta esplorabile, consultabile e salvabile. Non è ammesso
  in alcun ingresso Writer, né come contenuto musicale riproducibile in Writer.
  Free → melody è fuori da questa fase. L'import Free in Piano Roll resta
  fuori dal perimetro della richiesta.
- La chiave è tonica + scala/modo, persistente e condivisa nel progetto.
  Impostazione iniziale, modifica e rimozione da Writer/Fretboard/Piano
  richiedono conferma prima di cambiare la chiave del progetto. Dopo conferma
  tutti gli strumenti si aggiornano attraverso la configurazione condivisa.
- New project si sposta dal pulsante + al menu principale di Writer.
  Restano il flusso Piano/Fretboard e le protezioni Keep/Discard/Cancel.
- Si lavora con fresh start: non servono migrazioni o recupero dei vecchi
  salvataggi. Non è necessario cancellare dati esistenti per implementare.

## Evidenza iniziale

- `lib/features/songwriter/songwriter_screen_sheet.dart`:
  `_showCompatibleHarmonySaves` ammette solo `HarmonyChordSnapshot`;
  `_onTapBlock` abilita Change/Replace solo con root e quality presenti;
  `_PatternLaneRow` elenca tutte le Harmony Fretboard, anche quelle occupate.
- `lib/features/instrument_shared/writer_handoff.dart`:
  `_WriterTransferChoices` distingue accordo rilevato ed exact voicing;
  il secondo diventa Save/Voicing invece di Harmony.
- `lib/store/songwriter_store.dart`: `canAddGuitarStrumLane`,
  `setLaneAnchorLane` e `insertWriterBlockFromSave` non verificano l'esclusività;
  `_buildHarmonyChordSnapshot` e `_isPlayableHarmonyComposite` richiedono
  metadata di riconoscimento; `setKey` cambia solo il Writer.
- `lib/models/save_system.dart`: `FretboardSnapshot` non persiste `inputMode`.
  `FretboardNotifier.loadSnapshot` ripristina le note ma conserva il mode live.
  `setInputMode` non elimina selezioni multiple sulla stessa corda.
- `lib/store/project_config_sync.dart` sincronizza il progetto verso gli
  strumenti; non riceve i cambi di chiave dagli strumenti.
  `SharedScalePicker._tryApplyScale` promuove una scala al progetto soltanto
  se il progetto ha già una chiave. La detection scrive provider locali.
- `lib/features/songwriter/songwriter_header.dart` espone New project nel
  config strip e passa la chiave direttamente a `setKey`.
- Test manuale iniziale su iPhone 17 Pro, iOS 26.4: l'app si avvia; una nota
  in Free espone Add to Writer → Add exact voicing. Il test è stato annullato
  prima della creazione di blocchi. Writer mostra + e due strumming lane.

## 1. Contenuto Harmony e confine Free

Specialisti: state-architect, save-system e music-theory.

Riutilizzare il composito `HarmonyChordSnapshot`: contiene già
`WriterBlockSnapshot` e lo snapshot nativo. Root e quality possono essere
assenti; lo snapshot nativo conserva ottave, tasti e posizioni. Nessun nuovo
tipo di Save o duplicazione parallela del contenuto.

Distinguere accordo simbolico riconosciuto e Harmony di note esatte nelle
regole, senza usare la presenza di root/quality come requisito di riuso.
Una Harmony esatta deve avere selezione nativa non vuota e valida per lo
strumento. Non assegnare automaticamente un accordo sulla base del nome
dato dall'utente (es. "d#"). La successiva azione Change chord permette di
scegliere esplicitamente un accordo riconosciuto dal picker.

Persistire il mode Fretboard in ogni cattura e copia dello snapshot:

```dart
final FretboardInputMode inputMode;
// toJson
'inputMode': inputMode.name,
// loadSnapshot
inputMode: snap.inputMode,
```

Un valore serializzato assente o sconosciuto fallisce chiuso a Free. Questo
default non costituisce una migrazione e non rende importabili vecchi Save.
I fixture che rappresentano voicing validi per Writer devono dichiarare Chord.

Tutti i generatori di voicing Harmony impostano Chord; tutte le catture
strumento salvano il mode effettivo. Un Save Free non diventa eleggibile
perché la schermata live si trova in Chord. Una selezione Chord con più
posizioni sulla stessa corda, possibile dopo il cambio da Free, deve essere
rifiutata con una spiegazione, senza eliminare note automaticamente.

Centralizzare in `lib/schema/rules/` la validità della selezione nativa e
l'eleggibilità per Writer; riusare questa regola in UI, mutazioni, linked
edits e playback. Non impedire il normale salvataggio o caricamento Free.

File di produzione da modificare:

- `lib/models/save_system.dart` — campo mode e JSON Fretboard; chiarire il
  contratto del composito Harmony di note esatte.
- `lib/models/songwriter.dart` — consentire il reset esplicito della sola
  identità armonica nullable in `SongBlock.copyWith` (e nei copy helper che
  ne hanno bisogno), conservando nome e note esatte. L'attuale `??` non
  cancella root/quality passando null e `clearChordData` elimina anche le note.
- `lib/schema/rules/songwriter_rules.dart` — eligibility nativa, contenuto
  Harmony indipendente dal riconoscimento; composizione/resoluzione canonica.
- `lib/schema/rules/songwriter_voicing_rules.dart` — snapshot dei voicing
  generati esplicitamente in Chord.
- `lib/store/fretboard_store.dart` — cattura e ripristino mode.
- `lib/features/fretboard/fretboard_save_panel.dart` — cattura mode e gating
  Use in Writer in base al Save, non allo stato live.
- `lib/store/save_system_store.dart` — conservare mode nelle copie di snapshot
  e retrofit della configurazione di progetto.
- `lib/store/songwriter_store.dart` — handoff esatto verso Harmony,
  validazione/creazione/replace/update/reuse del composito; preservare mode
  nelle copie e rifiutare Free anche chiamando direttamente le API.
  Coprire `_buildHarmonyChordSnapshot`, `_validatedHarmonyInstrumentEdit`,
  `_withPendingChord`, `_hasChordContent`, `_isPlayableHarmonyComposite`,
  `insertInstrumentSelectionAtBar`, `insertWriterBlockFromSave`,
  `addSaveBlock`, `addLibraryBlockAt`, `_saveSnapshotMatchesAnchor`,
  `acceptLibraryMatch`, `updateLinkedSaveSnapshot` (e l'alias
  `updateLinkedInstrumentSave`) e le API di voicing. Tutte le guardie sono
  precedenti a creazione di lane/pattern/Save e step history.
  La modifica di un Save Fretboard già collegato non può passare a Free;
  può essere salvata separatamente come idea Free.
- `lib/features/instrument_shared/writer_handoff.dart` — exact selection
  Piano/Fretboard Chord verso Harmony, nome utente, riuso Save e guardie
  dopo i dialoghi asincroni. L'opzione exact esistente diventa exact Harmony;
  non si aggiunge una terza scelta equivalente.
- `lib/features/instrument_shared/shared_detection_panel.dart` e
  `instrument_binding.dart` — esporre disponibilità del Writer handoff;
  Free mostra una spiegazione del requisito Chord.
- `lib/features/piano/piano_save_panel.dart` — Use in Writer delle selezioni
  Piano non riconosciute verso Harmony, con il Save canonico corretto.
- `lib/features/songwriter/songwriter_screen_sheet.dart` — Library e tile
  uniformi, Change/Replace per Harmony esatta; strumenti di teoria/voicing
  che richiedono root/quality restano disponibili solo se quei dati esistono.
- `lib/ui/save_browser_panel.dart` — usare l'eligibility per Use in Writer
  anche nei menu/preview; riusare l'hook `canUseInWriter` già previsto.

Nome, note e contenuto nativo sono canonici nel Save; posizione, durata,
repeat e lyrics locali restano nel Writer. Gli aggiornamenti condivisi
continuano a usare la scelta all-uses/standalone e la coda journal esistenti.
Change e Replace non perdono lyrics o placement. Il riuso di un Save root
esistente conserva ID e cartella root, come nel contratto Use in Writer.

### Riuso di un Save nativo root

`startWriterHandoff` deve trattare il Save root Piano/Fretboard Chord
eleggibile come sorgente Harmony esatta. In
`SongwriterNotifier.insertInstrumentSelectionAtBar` / `_prepareWriterStructure`
preparare il suo nuovo `HarmonyChordSnapshot` senza pubblicare mutazioni
parziali: usare `adoptSaves` e il percorso journal già esistente per promuovere
il `SaveEntry` sotto lo stesso ID, mantenendo cartella root, note, nome e shape,
insieme al placement e ai writerLinks. Non scartare l'ID perché il suo tipo
precedente era nativo. Un secondo riuso collega lo stesso composito.

Prima del commit rileggere fonte, progetto, mode, contenuto e anchor degli
eventuali Save/Voicing link correnti. Il wrapper composito deve continuare a
far risolvere le note delle Save/Voicing lane collegate: la promozione non
può renderle silenziose. Rifiuto, Cancel e preflight fallito non modificano
Save, link o Writer. Le copie nel sync/baseline conservano note esatte e mode.
Testare serializzazione journal, riuso ripetuto, undo/redo del comando composto
e reload, senza duplicare il Save o perdere dati.

### Metadata e native edits

Un composito esatto valido ha nome non vuoto, note valide non vuote e root e
quality entrambi null; un metadata parziale è invalido. Per i riconosciuti
resta la validazione degli intervalli e del pitch set nativo.
`replaceHarmonyBlockWithSave`, `_applyCanonicalSnapshots`, materializzazione,
copy helper e restore devono cancellare root, quality e romano vecchi quando
la nuova identità è esatta, conservando label, note, posizione e lyrics.
Esempio di contratto per il nuovo flag nel copy helper:

```dart
currentBlock.copyWith(
  chordSymbol: content.chordSymbol,
  chordNotes: content.chordNotes,
  clearChordIdentity: content.chordRootPc == null &&
      content.chordQuality == null,
  chordRootPc: content.chordRootPc,
  chordQuality: content.chordQuality,
  romanNumeral: content.romanNumeral,
  clearRomanNumeral: content.romanNumeral == null,
);
```

`clearChordIdentity` azzera root/quality senza azzerare label/pitches;
`clearChordData` conserva il suo comportamento per blocchi silenziosi.
Un native edit di Harmony esatta aggiorna le pitch class dai tasti/posizioni
validi, mantiene nome scelto e root/quality/romano null e rimuove pendingChord
obsoleti. Non inferisce un accordo. Testare riconosciuto → esatto → riconosciuto,
refresh canonico, named-save materialization, history e reload.

## 2. Playback e import Song coerenti

Specialista: music-theory con state-architect.

Conservare il comportamento degli accordi simbolici già riconosciuti.
Per Harmony non riconosciuta usare i MIDI dello snapshot nativo canonico:
posizioni fisiche + tuning per Fretboard, selectedKeys per Piano. Non
ricostruire ottave dal solo insieme di pitch class.

Una funzione condivisa di risoluzione Harmony deve essere usata dal playback
Writer, dal lookup della Harmony negli strum e dall'import Writer → Song.
Schema indicativo:

```dart
List<int> harmonyBlockMidiNotes(/* block + scoped saves + folders */) {
  // Resolve the canonical composite, falling back only within project scope.
  // Reject ineligible Fretboard Free or invalid native selections.
  // Recognized chord: existing chordMidiNotes behavior.
  // Exact harmony: snapshotMidiNotes(composite.instrumentState).
}
```

File da modificare:

- `lib/schema/rules/songwriter_playback_rules.dart` — risoluzione condivisa,
  `_blockPitches`, `_harmonyAtTick`, gating Free e exact strum pitches.
- `lib/schema/rules/song_from_writer_rules.dart` — stessa risoluzione Harmony
  per track e strum; Free non crea note/clip riproducibili in Song.
- `lib/schema/rules/songwriter_rules.dart` — risoluzione musicale canonica
  di un blocco, inclusa Harmony senza root/quality. `resolveSnapshotChord`
  restituisce null per un composito esatto senza passare a `detectFirstChord`;
  i dati nativi non inventano identità o numeri romani.
- `lib/schema/rules/songwriter_library_match_rules.dart` — escludere Free
  dai suggerimenti importabili in Writer, preservando match riconosciuti.

Non cambiare `snapshotMidiNotes` globalmente in modo da bloccare gli usi
Free fuori Writer. Separare l'eligibility Writer dall'estrazione MIDI generica.
Estendere l'estrazione generica per unwrap dei compositi Harmony, preservando
le Save/Voicing lane che riusano un Save root promosso. Applicare il gate Free
nei soli percorsi musicali Writer. Entrambi i lookup Harmony per lo strum
(Writer e Song) devono usare il resolver comune con il contesto dei Save.

## 3. Esclusività del target strumming

Specialista: state-architect, poi instrument-renderer.

Una regola pura in `songwriter_rules.dart` restituisce le Harmony Fretboard
disponibili, escludendo anchor già usati da altre Guitar Strum lane nella
stessa sezione. L'eventuale `excludingLaneId` consente di mantenere la
sorgente attuale quando si modifica una lane.

```dart
List<SongLane> availableGuitarStrumHarmonyLanes(
  SongSection section, {
  required HarmonyLaneInstrument projectDefault,
  String? excludingLaneId,
});
```

File da modificare:

- `lib/schema/rules/songwriter_rules.dart` — regola disponibilità e
  validazione assegnazione; `null` resta Unassigned, anchor eliminato o
  incompatibile resta Unresolved, senza fallback impliciti.
- `lib/store/songwriter_store.dart` — `canAddGuitarStrumLane`, `addLane`,
  `setLaneAnchorLane` e `insertWriterBlockFromSave` verificano la regola
  prima di creare lane/pattern/Save o mutare lo stato. Un errore non lascia
  orfani e non aggiunge uno step undo. Le assegnazioni in sezioni diverse
  sono indipendenti. Rimozione/cambio anchor libera il target.
- `lib/features/songwriter/songwriter_screen_sheet.dart` — nascondere
  target occupati nel dropdown e usare lo stesso gate per Add Guitar Strum.
  Conservare sorgente propria, Unassigned e il messaggio Unresolved.
- `lib/features/instrument_shared/writer_handoff.dart` — se il picker dei
  Save pattern offre target strum, applicare la stessa regola e ricontrollare
  lo stato al commit.

Il riuso di uno stesso pattern sulla propria lane non occupa un altro target.
Più lane Unassigned possono esistere: null non riserva target e non si introduce
un limite totale alle lane. Il vincolo è l'assegnazione, ricontrollata al commit.
Mutazioni che spostano lane/sezioni devono mantenere l'invariante; verificare
le API già presenti senza introdurre nuove operazioni o migrazioni.

## 4. Chiave di progetto con conferma

Specialista: state-architect, poi instrument-renderer.

Usare `ProjectConfig` come fonte canonica. Una richiesta UI comune prepara
il cambio, mostra conferma per initial/change/clear e chiama il percorso
esistente `applyProjectConfig`. Il sync progetto → strumenti resta unico.
Root/scala incomplete nel picker sono soltanto una scelta in preparazione.

```dart
final nextConfig = requestedKey == null
    ? currentConfig.copyWith(clearKey: true)
    : currentConfig.copyWith(
        keyRootPc: requestedKey.rootPc,
        keyScaleName: requestedKey.scaleName,
      );
// After confirmation, verify the same project/config is still active.
await saveSystem.applyProjectConfig(projectId, nextConfig, retrofit: true);
```

File da modificare:

- `lib/ui/core/update_project_key_dialog.dart` — testi initial/change/clear;
  eventuale helper comune nello stesso file o in
  `lib/ui/core/project_key_change.dart` se serve a evitare duplicazione.
- `lib/features/instrument_shared/shared_scale_picker.dart` — promuovere
  anche la prima chiave di un progetto; clear passa dallo stesso percorso;
  annullamento ripristina la selezione confermata. In Dump/no-project
  mantenere l'esplorazione locale esistente.
- `lib/features/instrument_shared/shared_detection_panel.dart` — selezionare
  una scala rilevata nel progetto usa la conferma comune; non lasciare un
  pending locale capace di sovrascrivere la chiave confermata.
- `lib/features/songwriter/songwriter_header.dart` — il picker KEY modifica
  la chiave del progetto attraverso la richiesta comune; niente `setKey`
  locale quando c'è un progetto reale selezionato.
- `lib/store/project_config_sync.dart` — sincronizzare anche active/pending
  scale in Fretboard/Piano/Piano Roll, evitare vecchi callback microtask
  su progetti cambiati, propagare clear e pulire il contesto precedente
  passando a progetto senza chiave, Dump o nessun progetto. Un Save caricato con una scala
  precedente non deve cambiare la chiave condivisa di un progetto.
- `lib/features/fretboard/fretboard_save_panel.dart` e
  `lib/features/piano/piano_save_panel.dart` — caricamento scala coerente
  con autorità del progetto; niente promozione silenziosa di pendingScale.
- `lib/features/piano_roll/piano_roll_save_panel.dart` e
  `lib/store/piano_roll_store.dart` — il caricamento di un Save nello stesso
  progetto preserva chiave e highlight master e pulisce pending/activeScale
  obsoleti, conservando note e dati musicali. Non affidarsi a un successivo
  evento selectedProjectProvider, che in questo caso non avviene. Preservare
  il caricamento locale in Dump/no-project.
- `lib/store/save_system_store.dart` — nel retrofit Roll allineare o pulire
  `pendingScale` rispetto alla chiave master, senza ripristinare la scala
  precedente al primo load.
- `lib/store/songwriter_store.dart` — in `syncProjectConfig` ricomputare i
  numeri romani dopo il cambio chiave, senza riattivare history utente.

Annullare o chiudere il dialogo non cambia progetto, highlight confermato,
metadata, note scelte o salvataggi. Prima del commit ricontrollare mounted,
ID progetto e configurazione corrente; evitare di applicare una risposta
ritardata al progetto successivo o sovrascrivere altre modifiche config.
Non trasporre note. Preservare il comportamento esistente di history quando
la configurazione master cambia. Piano Roll e Song devono continuare a
ricevere la chiave come già previsto dal sync condiviso.

## 5. New project nel menu Writer

Specialista: instrument-renderer.

Modificare `lib/features/songwriter/songwriter_header.dart`:
rimuovere callback e + da `_WriterConfigStrip`; aggiungere New project a
`_showOverflowMenu`, chiudendo lo sheet prima di avviare
`showWriterProjectCreationFlow`. Dare al menu principale un tooltip/label
accessibile e un riferimento stabile per i test. Usare lo stesso ingresso
nel layout compatto landscape. Non duplicare il flusso di creazione.

Aggiornare i test che toccano `writerNewProjectButton` per passare dal menu.
Keep/Discard/Cancel e scelta dello strumento mantengono i test già esistenti.

## Test e criteri di completamento

Prima degli edit, ogni agente definisce il controllo minimo e aggiunge le
regressioni pertinenti vicino ai test esistenti, senza test che duplicano
soltanto l'implementazione.

| Area | Test da aggiornare/aggiungere | Criterio |
|---|---|---|
| Mode e native eligibility | `test/models/harmony_chord_snapshot_test.dart`, `songwriter_harmony_metadata_test.dart`, `save_system_project_test.dart`, test mirroring Fretboard/store/rules | Free/Chord round-trip; Chord generato; duplicati per corda e coordinate invalide rifiutati; caricare un Free non lo trasforma in Chord; API dirette addSaveBlock/addLibraryBlockAt/linked-edit rifiutano Free prima di mutare |
| Harmony sconosciuta | `test/store/songwriter_instrument_handoff_test.dart`, `songwriter_harmony_composite_store_test.dart`, `writer_save_sync_store_test.dart`, `songwriter_history_test.dart`, `writer_save_binding_store_test.dart` | Nome+note+shape preservati; root Save promosso una volta con ID/cartella conservati; link Save/Voicing restano udibili; metadata riconosciuto→esatto→riconosciuto corretti anche al refresh; shared Save, materializzazione e lyrics coerenti; undo/redo, journal e reload senza perdita |
| Menu e Library | `test/features/instrument_shared/writer_handoff_test.dart`, `shared_detection_panel_test.dart`, `test/features/songwriter/songwriter_from_library_test.dart`, `songwriter_lane_block_actions_test.dart`, `test/ui/save_browser_use_in_writer_target_test.dart` | Unknown selezionabile per slot successivi; Change/Replace presenti; Free bloccato anche nei menu Save; no confusione con blocco silenzioso |
| Playback/Song | `test/schema/rules/songwriter_playback_rules_test.dart`, `song_from_writer_rules_test.dart`, `test/store/songwriter_playback_test.dart` | Unknown exact MIDI coerenti in Harmony, strum e Song; accordi riconosciuti non regrediscono; Free non produce eventi Writer/Song |
| Strum exclusivity | `test/schema/rules/songwriter_rules_test.dart`, `test/store/songwriter_lane_ops_test.dart`, `test/features/songwriter/songwriter_pattern_lane_test.dart` | Self anchor visibile; altrui nascosto; API rifiuta occupato; no orfani; target libero dopo unassign/delete; sezioni indipendenti |
| Chiave | `test/store/project_config_sync_test.dart`, `test/features/instrument_shared/shared_scale_picker_test.dart`, `shared_detection_panel_test.dart`, `test/features/songwriter/songwriter_header_test.dart`, `test/features/piano_roll/piano_roll_save_panel_test.dart`, `test/store/save_system_project_config_apply_test.dart` | First/change/clear in tutte le direzioni; conferma/cancel; project switch durante dialogo; Save same-project reload in Piano/Fretboard/Roll preserva chiave/highlights/notes; riavvio; nessuna trasposizione; romano aggiornato |
| Project menu | `test/features/songwriter/songwriter_project_creation_ui_test.dart`, `songwriter_header_overflow_test.dart` | + assente; voce menu accessibile; flusso Keep/Discard/Cancel invariato; compact e wide |

Verifica automatica: `dart format <changed Dart files>`, suite Flutter mirata
per ogni fase; dopo integrazione `flutter analyze`, un'unica esecuzione della
suite interessata e `git diff --check`. Allargare i test solo in presenza di
nuovi cambi o rischi concreti. Nessuna nuova dipendenza prevista.

Verifica computer su simulatore già attivo, con progetto QA fresh separato:

1. New project dal menu; Cancel conserva il progetto; Keep/Discard testati.
2. Unknown Piano e Fretboard Chord → Writer; riuso Library in altro slot;
   Change/Replace e note/playback verificati con supporto dei test MIDI.
3. Free → Save → reload conserva Free; tutti i percorsi Writer sono bloccati;
   Chord non valido spiega il requisito senza eliminare note.
4. Due Harmony Fretboard, due strum: il secondo non offre il target occupato;
   liberare il primo target lo rende disponibile al secondo.
5. Chiave iniziale/change/clear da Writer, Piano e Fretboard, con conferma e
   Cancel; switch tra le tre tab e riapertura del progetto mostrano coerenza.
6. Portrait compatto e landscape wide: menu, Library, dialoghi e dropdown
   senza overflow; nessuna eccezione runtime. Screenshots di verifica.

## Documentazione

Aggiornare `PRODUCT.md`, `DESIGN.md` (principi Harmony/Free/chiave/menu),
`README.md`, `docs/songwriter.md`, `docs/song_writer_guide.md`,
  `docs/save_system.md`, `docs/fretboard.md`, `docs/piano.md`. Correggere le
descrizioni in conflitto (es. strum sorgente condivisibile e strumenti con
key controls bloccati). Riesaminare `AGENTS.md` dopo ciascuna fase; modificarlo
solo se emerge una regola persistente nuova, in forma concisa.

## Delegazione e review

Tutti gli agenti ricevono contesto fresh (`fork_turns: none`), istruzioni
esplicite e i riferimenti a piano, AGENTS e specialista. Non usano contesto
ereditato della conversazione.

1. Piano → reviewer GPT-6.1 Sol, reasoning extra high. Correggere i finding e
   sottoporre a un nuovo reviewer fresh finché APPROVED.
2. Sottoporre il piano approvato all'utente. Attendere la sua approvazione
   prima di qualsiasi edit al codice.
3. Implementazione GPT-6 Luna, reasoning extra high: primo agente stato/save
   Harmony+Free e playback; secondo agente strum; terzo agente chiave/menu.
   Le fasi che condividono `songwriter_store.dart`, `screen_sheet.dart`,
   binding o pannelli sono sequenziali, con ownership esplicita dei file.
   Documentazione e test viaggiano con ogni fase.
4. Review indipendenti GPT-6 Luna extra high fresh per stato/persistenza/
   musica e per UI/UX. Reviewer leggono il diff e il contratto approvato,
   senza modificare codice. Eseguire review accessibilità/code quality nei
   rispettivi domini.
5. Ogni finding concreto torna a un implementer GPT-6 Luna extra high fresh;
   ritestare la parte modificata, integrare e avviare altri reviewer fresh.
   Continuare finché entrambi passano e controlli/simulatore sono completati.
6. Riportare evidenza dei test e i limiti effettivi: la review passata significa
   nessun errore concreto trovato nel perimetro, non una garanzia assoluta.

## Registro review

- Review 1, GPT-6.1 Sol extra high, contesto fresh: NOT APPROVED. Richieste
  concrete: promozione journaled del Save root; metodi reali e copertura
  completa Free; reset metadata nullable e assenza di riconoscimento implicito;
  Roll same-project load e ricomputazione numeri romani.
- Revisione 2 del piano: integra tutte e quattro le correzioni. Il reviewer
  ha confermato la correttezza del vincolo strum come esclusività dei target,
  senza limite alle lane Unassigned, e la fattibilità della promozione root.
- Baseline pre-implementazione: 35 test esistenti passati su Harmony composite,
  instrument handoff, lane operations, project config sync e creazione progetto.
- Review 2, nuovo GPT-6.1 Sol extra high, contesto fresh: APPROVED.
  Nessuna correzione obbligatoria residua nel piano. Durante l'implementazione
  verificare anche il preflight centrale dei metodi generici restore/relink,
  senza aggiungere migrazioni o funzionalità non richieste.
- Approvazione dell'utente: ricevuta il 2026-10-04. Implementazione autorizzata.

## Registro implementazione e verifica

- Implementazione delegata ad agenti GPT-6 Luna extra high con contesto fresh:
  Harmony/Free e persistenza, UI Harmony, chiave/menu, esclusività strum.
  Nessuna migrazione dei salvataggi precedenti aggiunta.
- La prima suite completa ha rilevato 13 failure. Le fixture native incomplete
  sono state adeguate alla nuova validazione, preservando lo scopo dei test.
  Il test cross-lane con Save realmente collegati ha inoltre rilevato il menu
  Rename/Make Unique mancante per Melody/Strum; riparazione affidata a un nuovo
  agente fresh, con test cross-lane conservato.
- QA computer su iPhone 17 Pro, iOS 26.4, progetto isolato
  `Codex Harmony QA 2026-10-04`: New project nel menu e Cancel; Free salvato e
  riaperto senza Use in Writer; Harmony D# non riconosciuta con nome utente,
  riuso dalla Library e Change/Replace; Harmony Piano da una singola nota;
  modifica nativa che conserva la chiave corrente.
- QA chiave: conferma iniziale D# minore da Writer, Cancel senza modifica,
  sincronizzazione Fretboard/Piano; cambio E minore da Piano; clear da
  Fretboard; impostazione D dorico da Fretboard visibile anche in Writer.
  Nessuna trasposizione delle note selezionate.
- QA Free/Chord: due posizioni sulla stessa corda restano selezionate dopo
  il cambio modalità e impediscono l'import con spiegazione.
- QA strum dopo hot reload: due lane Unassigned; assegnazione della sorgente
  alla prima, sorgente nascosta nella seconda e visibile nella prima;
  Unassign libera il target, che diventa assegnabile alla seconda. Add guitar
  strum lane è assente quando tutte le fonti sono occupate.
- Layout controllati in verticale e orizzontale; playback avviato senza errori
  runtime. MIDI esatti e import Song sono verificati nei test automatici.
- Correzione menu collegati: 12 widget test passati; Rename/Make Unique Strum
  verificati anche nel simulatore dopo hot reload. Le ultime due fixture del
  Save Panel usavano due anchor identici: corrette con sorgenti distinte,
  conservando le assertion originali; 15 test mirati passati.
- Verifica conclusiva: `flutter test --no-pub --reporter expanded`, 1.211 test
  passati; `flutter analyze --no-pub`, nessun problema;
  `dart format --output=none --set-exit-if-changed` su tutti i 60 file Dart
  modificati, zero cambi; `git diff --check`, pulito.
- Il tentativo di avviare il primo reviewer fresh ha restituito
  `agent thread limit reached`, anche attraverso un agente esistente. Il
  fallback Codex CLI in un processo ephemeral/read-only ha rifiutato il
  modello GPT-6 Luna per questo account: nessuna review è stata prodotta.
  Richiesta autorizzazione all'utente per tre nuove chat fresh nello stesso
  progetto, dedicate alle review. Non dichiarare la review finale approvata.
