# Cinque direzioni per Muzician

**Aggiornamento 18 ottobre:** l’utente preferisce Studio. Vedi [estensione Piano Roll e palette Muzician](STUDIO.md) e [galleria](index.html).

Cinque alternative, ognuna composta da Fretboard, Piano e Writer. Le tavole esplorano sistemi alternativi: la coerenza è interna a ogni terna, mentre fra le terne cambiano gerarchia, layout e carattere. Nessuna proposta è stata implementata nell'app.

## 01 — Carta

**L'idea musicale come pagina di un quaderno.** Fondo avorio, inchiostro scuro, accento terracotta. Titoli e accordi con serif leggibile; controlli sans. Separazioni sottili, pochi contenitori.

Fretboard e Piano mettono lo strumento sopra un riepilogo armonico e un pannello voicing aperto. Writer avvicina accordi e parole come un foglio di canzone. La teoria rimane una nota di supporto al contenuto.

- Favorisce scrittura di testi, rilettura e composizione tranquilla.
- Rischio: una gerarchia troppo editoriale potrebbe nascondere controlli frequenti; dimensioni e densità vanno provate con una sezione lunga.
- Su tablet: pagina del brano accanto allo strumento/inspector, non duplicazione di carte.

[Tavola Carta](mockups/01-carta.png)

## 02 — Studio

**Un banco di lavoro compatto.** Grafite neutra, menta per selezione, accento ambra per la fondamentale. Sans tecnica con numeri monospaziati; bordi sobri e poca decorazione.

Gli strumenti condividono un inspector a tab Notes/Voicings/Setup. Writer rende visibili lane, riferimenti e pattern; lo strum si legge in quattro gruppi di quattro passi. Un'azione primaria rimane stabile sopra la navigazione.

- Favorisce chi alterna spesso voicing, pattern e ascolto.
- Rischio: densità e terminologia possono intimidire; l'empty state deve restare semplice.
- Su tablet: inspector laterale persistente e timeline più ampia, senza introdurre una console DAW completa.

[Tavola Studio](mockups/02-studio.png)

## 03 — Focus

**Una sequenza chiara: suona, scegli la forma, usa l'idea.** Bianco freddo, blu deciso, controlli familiari e testo leggibile. Le etichette Play/Shape/Use sono raggruppamenti proposti, non nuove destinazioni.

Negli strumenti un accordion aperto raccoglie i voicing. Writer lascia visibili sezione e accordi mentre un pannello contestuale offre le azioni sul blocco. I comandi di modifica hanno etichette esplicite.

- Favorisce scoperta e uso occasionale; rende il passaggio al Writer più evidente.
- Rischio: maggiore spazio e disclosure possono aumentare i tap dell'utente esperto.
- Su tablet: le tre aree si affiancano quando utile, conservando l'ordine di lettura.

[Tavola Focus](mockups/03-focus.png)

## 04 — Session

**Lo strumento resta al centro durante una prova.** Verde bosco, testo osso e giallo chiaro per l'azione. Superfici piatte e controlli forti, senza effetti luminosi.

Il canvas occupa la metà superiore; sotto, un drawer contestuale ospita Scale/Chord/Setup. Writer riusa lo stesso meccanismo per Pattern/Source/Mixer. Il contesto rimane visibile e il comando principale è raggiungibile nella parte bassa.

- Favorisce uso con una mano e alternanza rapida tra suonare e modificare.
- Rischio: competizione fra drawer e navigazione globale; verificare tastiera software, landscape e schermi piccoli.
- Su tablet: drawer trasformato in inspector laterale, mantenendo lo strumento grande.

[Tavola Session](mockups/04-session.png)

## 05 — Forma

**La struttura musicale diventa la griglia della pagina.** Bianco sporco, nero e arancio; bordi netti, tipografia sans e metadati monospaziati. Celle e righe seguono battute e sezioni.

Fretboard e Piano separano la superficie dall'area dettagli, con riepilogo accordo accanto ai voicing. Writer è una tabella musicale con armonia, parole e strum allineati. L'editor selezionato occupa una fascia dedicata.

- Favorisce confronto, scansione rapida e chiarezza della struttura.
- Rischio: celle troppo rigide con testi lunghi, nomi personalizzati o scala del testo maggiore.
- Su tablet: colonna della struttura e griglia estesa, con inspector agganciato alla selezione.

[Tavola Forma](mockups/05-forma.png)

## Confronto e scelta

| Direzione | Priorità | Organizzazione dei pannelli | Compromesso principale |
| --- | --- | --- | --- |
| Carta | Accordi + testo | Sezioni della pagina | Meno densità operativa |
| Studio | Controllo rapido | Inspector a tab | Maggiore complessità percepita |
| Focus | Comprensione del flusso | Accordion e azioni nominate | Più disclosure |
| Session | Superficie suonabile | Drawer contestuale | Poco spazio verticale |
| Forma | Struttura e confronto | Griglia + fascia dettaglio | Reflow di testi lunghi |

Per un primo prototipo consiglierei **Carta** se la priorità è scrivere canzoni, oppure **Studio** se prevale l'esplorazione strumentale e dei pattern. **Focus** è il riferimento da usare per verificare che le altre direzioni restino comprensibili. Questa è una valutazione progettuale, non il risultato di un test con utenti.

## Cosa rimane da verificare in un prototipo

Le immagini definiscono direzione e gerarchia, non specifiche al pixel. Il motore musicale resta quello dell'app. Prima di scegliere: provare una selezione Free non trasferibile, un Exact Harmony senza identità, un nome lungo, una modifica condivisa, una sezione con più lane e versi, un pattern non assegnato, uno stato senza tonalità. Verificare target ≥44 pt, VoiceOver, contrasto, Dynamic Type, viewport compatta e larga.

La sorgente dello strum è assegnata a Harmony 1 nelle tavole per rappresentare uno stato utilizzabile; nel progetto osservato era Unassigned. Standard/capo 0 è un'altra normalizzazione illustrativa. “Save idea”, “Save version” e i nuovi raggruppamenti sono etichette proposte per separare operazioni già esistenti. Il percorso riconosciuto/Exact deve rimanere disponibile nel dialogo successivo ad Add to Writer, anche quando non compare nella vista principale.

Prompt e metodo: [PROMPTS.md](PROMPTS.md). Evidenze e vincoli: [ANALISI.md](ANALISI.md).
