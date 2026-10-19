---
name: grok-hub
description: Manda richieste ai bot Grok Bot di Federico (@grok-bot, @raimondo (Il Piccolo Raimondo Vianello), @piano-rilancio, @network, @ricercatore, @copywriter, @marketer, @developer, @home-assistant, @vendite-usato, @nutrizionista, @competitor-watch, @caso-carplay, @projects-manager) o mostra le loro risposte in richieste.md del repo grok-claude-hub. Usala quando Federico usa un comando /grok:… o chiede di "chiedere al bot X" o di vedere le risposte dei bot.
---

Rispondi a Federico in italiano, in poche righe. Le regole del file `richieste.md` sono in `HANDOFF.md` del repo grok-claude-hub.

Il lavoro lo fa il connettore locale **grok-hub** di questo plugin, che gira sul PC Windows di Federico (dove ci sono Git, l'accesso GitHub e le variabili `GROK_WEBHOOK_URL` / `GROK_WEBHOOK_KEY`). Non cercare di fare le stesse cose dalla shell di Cowork: lì non ci sono né le credenziali né le variabili.

## Mandare una richiesta

1. Se Federico non ha scritto la richiesta, chiedigliela in una riga.
2. Chiama lo strumento `grok_invia` del connettore grok-hub con:
   - `per`: il bot (per esempio `@network`). Elenco completo e id in `HANDOFF.md`; "raimondo" o "il piccolo raimondo vianello" = `@raimondo`. Se Federico nomina un bot che non conosci, **non rifiutare e non dire che non esiste**: passa il nome così com'è in `per`, il connettore lo manda a `@grok-bot` che lo smista;
   - `testo`: la richiesta così come l'ha scritta Federico (non riassumerla, non aggiungere password, token o dati sanitari);
   - `file`: solo se la richiesta cita un file del repo, il suo percorso;
   - `argomento`: 3-6 parole per il messaggio di commit.
   Lo strumento aggiunge la sezione `## AAAA-MM-GG HH:MM · @bot · aperta` in fondo a `richieste.md` (ora di Roma), fa commit e push e avvisa il bot.
3. **Aspetta tu la risposta e riportala in chat.** `grok_invia` aspetta già la risposta per circa 50 secondi (Claude Desktop interrompe gli strumenti dopo un minuto):
   - se il risultato dice **RISPOSTA ARRIVATA**, riporta a Federico la risposta del bot così com'è, in italiano, senza riassumerla e senza commenti;
   - se dice **IN ATTESA**, chiama subito `grok_attendi` con `per` e `ora` indicati nel risultato, e richiamalo ogni volta che risponde IN ATTESA, finché la risposta arriva (di solito 1-3 minuti). Mentre aspetti non scrivere niente a Federico e non chiedergli nulla;
   - se dice di smettere di aspettare (dopo circa 20 minuti), di' a Federico in una riga che il bot non ha ancora risposto.
   Non dire mai a Federico di usare `/grok:risposte` o di guardare lui `richieste.md`: la risposta gliela porti tu.
   Se lo strumento dice che il push non è riuscito, non riprovare da solo: riferisci il motivo in due righe e di' che il prossimo invio spinge anche questa richiesta.

## Mostrare le risposte

1. Chiama lo strumento `grok_richieste` del connettore grok-hub. Non modificare nessun file.
2. Ogni richiesta è una sezione `## AAAA-MM-GG HH:MM · @bot · aperta|fatta`; se è fatta, sotto c'è `**Risposta (@bot, data ora):** …`.
3. Mostra due elenchi brevi, dal più recente: **Aperte** (data, bot, richiesta in una riga) e **Fatte** (data, bot, richiesta in una riga, risposta in 1-2 righe). Se Federico ha scritto un filtro (nome di un bot o una parola), mostra per intero solo le sezioni che corrispondono.

## Se gli strumenti grok-hub non ci sono o danno errore

Non modificare `richieste.md` a mano e non usare curl dalla shell. Di' a Federico cosa controllare:
- che Claude Desktop sia aperto sul PC Windows (il connettore gira lì);
- in **Customize > Plugins > Grok Bot**, scheda **Connectors**, che `grok-hub` sia attivo;
- che il repo sia clonato in `C:\Users\<utente>\grok-claude-hub` (oppure che la variabile `GROK_HUB_DIR` punti alla cartella giusta) e che Git per Windows sia installato;
- che un `git push` fatto a mano da quella cartella funzioni senza chiedere la password (Git Credential Manager);
- dopo aver impostato le variabili di Windows, di chiudere del tutto Claude Desktop (anche dall'icona vicino all'orologio) e riaprirlo.
I passi di installazione completi sono nel `README.md` del repo, sezione "Usare i bot da Claude Cowork".
