# Plugin Grok Bot per Claude Cowork

Comandi per chiamare i bot Grok Bot di Federico da Claude Cowork (app desktop Claude, Windows). In Claude Code sul repo restano anche i comandi `/grok-<nome>` di `.claude/skills/`.

## Comandi

`/grok:bot`, `/grok:piano-rilancio`, `/grok:network`, `/grok:ricercatore`, `/grok:copywriter`, `/grok:marketer`, `/grok:developer`, `/grok:home-assistant`, `/grok:vendite-usato`, `/grok:nutrizionista`, `/grok:raimondo`, `/grok:competitor-watch`, `/grok:caso-carplay`, `/grok:projects-manager`, `/grok:nexum`, `/grok:startup-ai-pmi` seguiti dalla richiesta (elenco con gli id in `HANDOFF.md`; un nome sconosciuto va a Grok Bot che lo smista); Claude aspetta la risposta del bot e la riporta in chat; `/grok:risposte` mostra tutte le richieste. In Cowork si può anche scrivere a parole, per esempio "chiedi al network di trovarmi 3 eventi PMI a Udine".

## Installazione

I passi completi per Federico sono nel `README.md` della radice del repo, sezione "Usare i bot da Claude Cowork". In breve: Claude Desktop > **Customize > Plugins > Add > Add marketplace** con `fedmor95-alt/grok-claude-hub`, poi attivare il connettore `grok-hub` nella scheda **Connectors**. Da Claude Code: `/plugin install grok --marketplace fedmor95-alt/grok-claude-hub`.

## Come funziona

Il plugin contiene un connettore locale, `grok-hub` (`mcp/grok-hub.ps1`, PowerShell, compatibile con Windows PowerShell 5.1), che Claude Desktop avvia sul PC Windows. Il connettore aggiunge la richiesta in fondo a `richieste.md` nel clone `C:\Users\<utente>\grok-claude-hub` (oppure nella cartella della variabile `GROK_HUB_DIR`), fa commit e push e avvisa la routine Grok "Richieste da Claude" con il webhook (`GROK_WEBHOOK_URL` e `GROK_WEBHOOK_KEY`, variabili utente di Windows). Serve il connettore perché la shell di Cowork gira nel cloud di Anthropic: non vede le variabili di Windows, non ha l'accesso GitHub del PC e la sua rete è limitata.

Se il push non riesce, il connettore non chiama il webhook: la richiesta resta committata in locale e parte con l'invio successivo. Gli errori del connettore finiscono nei log di Claude Desktop con il prefisso `[grok-hub]`, mai con chiavi o indirizzi.

Nota per chi modifica `mcp/grok-hub.ps1`: il file va salvato in UTF-8 **con BOM**, altrimenti Windows PowerShell 5.1 legge male il carattere `·` dei titoli di `richieste.md`.

## Dati

Il testo delle richieste va su GitHub (repo privato `fedmor95-alt/grok-claude-hub`) e alla routine Grok Bot. Il plugin non contiene chiavi: le legge da Windows.
