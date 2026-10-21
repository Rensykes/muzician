# Studio — Piano Roll e palette Muzician

18 ottobre 2026. Direzione preferita dall'utente: **02 Studio**. Questa preferenza guida l'esplorazione; non è ancora un redesign implementato né una sostituzione di DESIGN.md.

## Nuove tavole

- [Piano Roll — Studio grafite/menta](mockups/06-studio-piano-roll.png)
- [Fretboard, Piano, Writer — Studio con palette Muzician](mockups/07-studio-muzician.png)
- [Piano Roll — Studio con palette Muzician](mockups/08-studio-muzician-piano-roll.png)
- [Galleria di confronto](index.html)

La variante cromatica conserva l'organizzazione Studio: canvas musicale dominante, pannelli compatti, bordi sottili, etichette esplicite. Riprende night/indigo, sky, teal, violet ed emerald del [tema corrente](../../../lib/theme/muzician_theme.dart). Le immagini approssimano questi token; i valori da implementare restano quelli del codice.

## Piano Roll: confronto con le funzioni reali

La griglia usa tempo sull'asse orizzontale e pitch su quello verticale. Default: quattro battute, 120 BPM, C3–C6; la tavola mostra una porzione C4–C5. Un tick corrisponde a un sedicesimo in 4/4. La colonna selezionata guida detection e inserimento, mentre le note selezionate guidano modifica e cancellazione: sono stati distinti.

Draw, Select, Split, Paint e Delete sono implementati. La tavola rende immediati Draw/Select/Scissors e riserva gli altri a Tools. La griglia permette spostamento, ridimensionamento, selezione multipla, taglio, scroll e pinch. Il trasporto reale include rewind, stop, play, BPM e metro; il mockup compatta questa area e non mostra rewind. Il metronomo oggi è in Settings: averlo nel trasporto è una proposta di accesso rapido.

Lo Stack Builder costruisce accordi o combinazioni personalizzate con fondamentale, qualità, inversione e durata. Add Stack inserisce nella colonna scelta o nella prima libera. Quick copia la selezione o ripete l'ultimo stack; non appare in questa tavola, ma va mantenuto nel prototipo. Le etichette Chord/Custom traducono e semplificano Canonico/Avanzato. Il controllo Octave nella vista compatta è una proposta di raggruppamento, non una riproduzione esatta del pannello corrente.

Snap esiste a 1/2/4/8/16/32 tick. Oggi è accessibile nel pannello wide: portarlo nella toolbar mobile è una proposta di accessibilità di un controllo esistente. Anche il range ±1 ottava deve restare raggiungibile da Tools. Detect analizza la colonna, non l'intera timeline.

**Record apre Hum Recorder**, che trascrive canticchio monofonico in note. Non è registrazione di una traccia audio Writer né registrazione MIDI da tastiera. Save salva il Roll; Import carica dai Save in modalità Exact MIDI/Pitch Class. Non è previsto un Add to Writer automatico da questa schermata.

Fonti: [screen_v2](../../../lib/features/piano_roll/piano_roll_screen_v2.dart), [grid](../../../lib/features/piano_roll/piano_roll_grid.dart), [Stack Builder](../../../lib/features/piano_roll/piano_roll_stack_builder.dart), [builder store](../../../lib/store/piano_roll_stack_builder_store.dart), [Hum Recorder](../../../lib/features/piano_roll/piano_roll_hum_recorder.dart), [regole](../../../lib/schema/rules/piano_roll_rules.dart). Verifica di questa estensione: lettura del codice, non nuova sessione interattiva sul simulatore.

## Mappatura cromatica

| Ruolo | Colore corrente |
| --- | --- |
| Canvas / surface / inspector | #0A0A1E / #0A0F1E / #161B2E |
| Testo primario / secondario | #F1F5F9 / #94A3B8 |
| Azione e navigazione attiva | Sky #38BDF8 |
| Note Roll normali | Teal #4ECDC4 |
| Note attive nella colonna selezionata | Emerald #34D399 |
| Selezione singola / multipla | Sky #38BDF8 / Violet #A78BFA |
| Playhead in riproduzione | Orange #FB923C |
| Harmony | Violet #A78BFA |

## Verifica visuale e limiti

Le tre immagini sono state ispezionate: schermate complete, testo principale leggibile, navigazione visibile e continuità Studio mantenuta. Nella tavola Muzician sono stati corretti il comando Add to Writer erroneamente presente dentro Writer nel concept iniziale e i tab Timing/Sound, sostituiti da Pattern/Source/Mixer.

Restano approssimazioni del generatore: il diagramma grande Fretboard non riproduce correttamente x32010 nonostante la richiesta; alcuni diagrammi piccoli e l'allineamento di A4 nella griglia Roll non sono precisi. Il pattern a 16 passi è troppo compatto per attestare target touch adeguati. Le durate disegnate e le suddivisioni non sono una specifica musicale. Queste immagini servono a valutare impianto e palette; nel prototipo i renderer esistenti devono generare geometria e note esatte. Non sono state misurate conformità di contrasto o dimensioni dei target sulle immagini.

Il mockup Studio iniziale includeva inoltre dettagli proposti o generati che non attestano funzioni esistenti: controlli di trasporto condivisi negli strumenti, Timing/Sound e Add to Writer nel Writer. L'analisi funzionale e il codice prevalgono sulle immagini.

Generazione: tool integrato imagegen, senza fallback CLI. [Prompt completi](PROMPTS-STUDIO.md).
