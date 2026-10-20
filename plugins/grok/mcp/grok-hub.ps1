# grok-hub.ps1 — piccolo server MCP locale (stdio) per Claude Cowork / Claude Desktop su Windows.
# Gira sul PC di Federico, quindi vede Git, l'accesso GitHub e le variabili utente di Windows
# GROK_WEBHOOK_URL e GROK_WEBHOOK_KEY (che non vengono mai stampate).
# Strumenti:
#   grok_invia     aggiunge una richiesta in fondo a richieste.md, fa commit e push, avvisa il bot via webhook
#                  poi aspetta la risposta (git pull ogni ~10 s) e, se arriva in tempo, la restituisce
#   grok_attendi   aspetta ancora la risposta a una richiesta già inviata (da chiamare finché arriva)
#   grok_richieste fa git pull e restituisce richieste.md
# Attesa: Claude Desktop / Cowork interrompe le chiamate agli strumenti dopo ~60 s (limite fisso del client,
# le notifiche di avanzamento non lo allungano), quindi ogni chiamata aspetta al massimo ~50 s
# (variabile GROK_HUB_WAIT_S) e, se la risposta non c'è ancora, dice a Claude di chiamare grok_attendi.
# Cartella del repo: variabile GROK_HUB_DIR, altrimenti %USERPROFILE%\grok-claude-hub.
# Stesso formato di HANDOFF.md e degli script in .claude/scripts/ (payload {per, file, testo}, Authorization: Bearer).
# Compatibile con Windows PowerShell 5.1 e PowerShell 7.
# NOTA: questo file va salvato in UTF-8 CON BOM. Windows PowerShell 5.1 legge gli script senza BOM come ANSI
# e il carattere "·" dei titoli di richieste.md verrebbe scritto sbagliato. Tutto ciò che lo script scrive
# (stdout, richieste.md, webhook) è invece UTF-8 senza BOM.

$ErrorActionPreference = 'Stop'
$ProgressPreference = 'SilentlyContinue'
try { [Net.ServicePointManager]::SecurityProtocol = [Net.ServicePointManager]::SecurityProtocol -bor [Net.SecurityProtocolType]::Tls12 } catch {}

function Get-EnvValueEarly([string]$Name) { return [Environment]::GetEnvironmentVariable($Name) }
$Utf8 = New-Object System.Text.UTF8Encoding $false
$In  = New-Object System.IO.StreamReader([Console]::OpenStandardInput(), $Utf8)
$Out = New-Object System.IO.StreamWriter([Console]::OpenStandardOutput(), $Utf8)
$Out.AutoFlush = $true
$Out.NewLine = "`n"
$File = 'richieste.md'
# Bot Grok Bot di Federico: @nome -> nome completo e id del bot (stesso elenco di HANDOFF.md).
$BotInfo = [ordered]@{
  '@grok-bot'         = 'Grok Bot (bot principale, smista agli altri)'
  '@raimondo'         = 'Il Piccolo Raimondo Vianello (06a5fd94-0f1b-4adf-9f70-9e5ea4c8d10b)'
  '@home-assistant'   = 'Home Assistant (157d574f-708e-4be2-bfef-58d8a82d7d98)'
  '@vendite-usato'    = 'Vendite usato (1e613545-1234-4958-baa0-086c212d8ae6)'
  '@network'          = 'Network (218a3662-475f-4d67-81d3-2f0cb597ad1b)'
  '@ricercatore'      = 'Ricercatore (4f25004a-1c42-4555-9dfc-745fe006918c)'
  '@nutrizionista'    = 'Nutrizionista e Personal Trainer (5a55c253-a128-485f-9d26-201462b612a1)'
  '@developer'        = 'Developer (7fbe8645-18ae-4caf-aa0c-47b77bd5b59d)'
  '@competitor-watch' = 'Competitor Watch (839295bb-e559-4e80-9f82-3693bc641489)'
  '@copywriter'       = 'Copywriter (8ff50101-2616-4189-bb05-72b48be07c00)'
  '@caso-carplay'     = 'Caso CarPlay (b41290d8-9866-415a-8c1e-82dfdef6a6e4)'
  '@projects-manager' = 'Projects Manager (b591164b-0284-4c17-9b3b-0c87af2e4dec)'
  '@marketer'         = 'Marketer (c61d6edf-419d-4e55-92be-c24f041bbd66)'
  '@nexum'            = 'Nexum (3ad7a864-a380-4bd8-b22a-f01a759bf833)'
  '@piano-rilancio'   = 'Piano rilancio (e8c08ae2-054f-49e1-979a-6ba817d0c2a0)'
}
$Bots = @($BotInfo.Keys)
# Alias (minuscolo, senza @): nomi completi e varianti comuni.
$Alias = @{
  'grok' = '@grok-bot'; 'grok bot' = '@grok-bot'; 'bot' = '@grok-bot'
  'raimondo' = '@raimondo'; 'il piccolo raimondo vianello' = '@raimondo'; 'piccolo raimondo vianello' = '@raimondo'; 'raimondo vianello' = '@raimondo'; 'il piccolo raimondo' = '@raimondo'
  'home assistant' = '@home-assistant'; 'vendite usato' = '@vendite-usato'; 'vendite' = '@vendite-usato'
  'nutrizionista e personal trainer' = '@nutrizionista'; 'personal trainer' = '@nutrizionista'
  'competitor watch' = '@competitor-watch'; 'competitor' = '@competitor-watch'
  'caso carplay' = '@caso-carplay'; 'carplay' = '@caso-carplay'
  'projects manager' = '@projects-manager'; 'project manager' = '@projects-manager'
  'nexum' = '@nexum'
  'piano rilancio' = '@piano-rilancio'; 'rilancio' = '@piano-rilancio'
}
$ElencoBot = ($BotInfo.GetEnumerator() | ForEach-Object { "$($_.Key) = $($_.Value)" }) -join '; '

# Risolve il destinatario: @nome noto, alias, oppure nome sconosciuto -> @grok-bot che lo smista.
# Restituisce @{ per = '@...'; inoltro = '<nome originale>' o $null }.
function Resolve-Bot([string]$Nome) {
  $n = ([string]$Nome).Trim()
  if (-not $n) { return $null }
  $k = $n.ToLowerInvariant().TrimStart('@').Trim()
  if ($Bots -contains "@$k") { return @{ per = "@$k"; inoltro = $null } }
  $k2 = ($k -replace '[-_]+', ' ' -replace '\s+', ' ').Trim()
  if ($Alias.ContainsKey($k2)) { return @{ per = $Alias[$k2]; inoltro = $null } }
  $k3 = ($k2 -replace ' ', '-')
  if ($Bots -contains "@$k3") { return @{ per = "@$k3"; inoltro = $null } }
  return @{ per = '@grok-bot'; inoltro = $n.TrimStart('@') }
}
$Versioni = @('2024-11-05','2025-03-26','2025-06-18')
$GitTimeoutMs = 180000
$AttesaS = 50; try { $w = [int](Get-EnvValueEarly 'GROK_HUB_WAIT_S'); if ($w -gt 0) { $AttesaS = $w } } catch {}
$PollS = 10;  try { $w = [int](Get-EnvValueEarly 'GROK_HUB_POLL_S'); if ($w -gt 0) { $PollS = $w } } catch {}
$MaxAttesaMin = 20   # dopo tanti minuti dall'invio smette di chiedere a Claude di aspettare
$ProgressToken = $null

# Messaggi di servizio su stderr (Claude Desktop li mette nei suoi log). Mai segreti.
function Write-Log([string]$Msg) { try { [Console]::Error.WriteLine("[grok-hub] $Msg") } catch {} }

function Get-EnvValue([string]$Name) {
  # Prima il processo, poi le variabili utente di Windows (se Claude Desktop è stato aperto prima di impostarle).
  $v = [Environment]::GetEnvironmentVariable($Name)
  if (-not $v) { try { $v = [Environment]::GetEnvironmentVariable($Name, 'User') } catch {} }
  return $v
}

function Get-RepoDir {
  $d = Get-EnvValue 'GROK_HUB_DIR'
  if ($d) { return $d }
  $h = $env:USERPROFILE; if (-not $h) { $h = $HOME }
  return (Join-Path $h 'grok-claude-hub')
}

function Test-Git {
  if (-not (Get-Command git -ErrorAction SilentlyContinue)) {
    throw 'Git non trovato sul PC (comando "git" non nel PATH). Installa Git per Windows e riapri Claude Desktop.'
  }
}

# Riga di comando per CreateProcess su Windows (regole di CommandLineToArgvW), valida anche su pwsh/Linux.
function ConvertTo-ArgString([string[]]$Items) {
  $parts = @()
  foreach ($s in $Items) {
    if ($s.Length -gt 0 -and $s -notmatch '[\s"]') { $parts += $s; continue }
    $sb = '"'; $bs = 0
    foreach ($ch in $s.ToCharArray()) {
      if ($ch -eq '\') { $bs++; continue }
      if ($ch -eq '"') { $sb += ('\' * (2 * $bs + 1)) + '"'; $bs = 0; continue }
      $sb += ('\' * $bs) + $ch; $bs = 0
    }
    $parts += $sb + ('\' * (2 * $bs)) + '"'
  }
  return ($parts -join ' ')
}

# Esegue git nella cartella del repo. $StdinText (facoltativo) viene passato a git su stdin in UTF-8.
function Invoke-Git([string]$Dir, [string[]]$GitArgs, [string]$StdinText = $null, [int]$TimeoutMs = 0) {
  if ($TimeoutMs -le 0) { $TimeoutMs = $GitTimeoutMs }
  $psi = New-Object System.Diagnostics.ProcessStartInfo
  $psi.FileName = 'git'
  $psi.Arguments = (ConvertTo-ArgString $GitArgs)
  $psi.WorkingDirectory = $Dir
  $psi.UseShellExecute = $false
  $psi.CreateNoWindow = $true
  $psi.RedirectStandardOutput = $true
  $psi.RedirectStandardError = $true
  $psi.RedirectStandardInput = $true
  $psi.StandardOutputEncoding = $Utf8
  $psi.StandardErrorEncoding = $Utf8
  $psi.EnvironmentVariables['GIT_TERMINAL_PROMPT'] = '0'
  $p = [System.Diagnostics.Process]::Start($psi)
  $o = $p.StandardOutput.ReadToEndAsync(); $e = $p.StandardError.ReadToEndAsync()
  if ($null -ne $StdinText -and $StdinText.Length -gt 0) {
    $b = $Utf8.GetBytes($StdinText)
    $p.StandardInput.BaseStream.Write($b, 0, $b.Length)
    $p.StandardInput.BaseStream.Flush()
  }
  $p.StandardInput.Close()
  if (-not $p.WaitForExit($TimeoutMs)) {
    try { $p.Kill() } catch {}
    return @{ ok = $false; text = "git $($GitArgs[0]) non ha risposto entro $([int]($TimeoutMs/1000)) secondi (forse aspettava una password o una conferma) ed è stato interrotto." }
  }
  $p.WaitForExit()
  return @{ ok = ($p.ExitCode -eq 0); text = (($o.Result + "`n" + $e.Result).Trim()) }
}

function Get-RomeNow {
  $tz = $null
  foreach ($id in @('W. Europe Standard Time','Europe/Rome')) { try { $tz = [TimeZoneInfo]::FindSystemTimeZoneById($id); break } catch {} }
  $now = [DateTime]::UtcNow
  if ($tz) { $now = [TimeZoneInfo]::ConvertTimeFromUtc($now, $tz) }
  return $now
}
function Get-RomeTime { return (Get-RomeNow).ToString('yyyy-MM-dd HH:mm') }

# Cerca in richieste.md l'ultima sezione con titolo "## <ora> · <per> · aperta|fatta".
# Restituisce $null se non c'è, altrimenti @{ fatta; risposta } (risposta = dal blocco **Risposta in giù, o $null).
function Find-Risposta([string]$Testo, [string]$Ora, [string]$Per) {
  $righe = $Testo -split "`r?`n"
  $pat = '^##\s+' + [regex]::Escape($Ora) + '\s+·\s+' + [regex]::Escape($Per) + '\s+·\s+(aperta|fatta)\s*$'
  $start = -1; $stato = ''
  for ($i = 0; $i -lt $righe.Length; $i++) { if ($righe[$i] -match $pat) { $start = $i; $stato = $Matches[1] } }
  if ($start -lt 0) { return $null }
  $end = $righe.Length
  for ($i = $start + 1; $i -lt $righe.Length; $i++) { if ($righe[$i] -match '^##\s') { $end = $i; break } }
  $corpo = @(); if ($end -gt $start + 1) { $corpo = $righe[($start + 1)..($end - 1)] }
  $r = -1
  for ($i = 0; $i -lt $corpo.Length; $i++) { if ($corpo[$i] -match '^\s*\*\*Risposta') { $r = $i; break } }
  $risp = $null
  if ($r -ge 0) { $risp = (($corpo[$r..($corpo.Length - 1)]) -join "`n").Trim() }
  elseif ($stato -eq 'fatta') { $risp = ($corpo -join "`n").Trim() }
  return @{ fatta = ($stato -eq 'fatta'); risposta = $risp }
}

function Send-Progress([int]$Fatto, [string]$Msg) {
  if ($null -eq $ProgressToken) { return }
  try { Send-Msg @{ jsonrpc = '2.0'; method = 'notifications/progress'; params = @{ progressToken = $ProgressToken; progress = $Fatto; message = $Msg } } } catch {}
}

# Aspetta (git pull ogni $PollS secondi) la risposta alla richiesta "<ora> · <per>" fino a $Scadenza.
function Wait-Risposta([string]$Dir, [string]$Ora, [string]$Per, [DateTime]$Scadenza) {
  $path = Join-Path $Dir $File
  $giro = 0
  while ($true) {
    $t = [IO.File]::ReadAllText($path, $Utf8)
    $f = Find-Risposta $t $Ora $Per
    if ($null -eq $f) { return @{ trovata = $false; manca = $true } }
    if ($f.risposta) { return @{ trovata = $true; testo = $f.risposta } }
    $resto = ($Scadenza - [DateTime]::UtcNow).TotalSeconds
    if ($resto -lt 3) { return @{ trovata = $false; manca = $false } }
    Start-Sleep -Milliseconds ([int]([Math]::Min($PollS, $resto - 2) * 1000))
    $giro++; Send-Progress $giro 'aspetto la risposta del bot'
    $resto = ($Scadenza - [DateTime]::UtcNow).TotalSeconds
    if ($resto -lt 2) { $resto = 2 }
    $null = Invoke-Git $Dir @('pull','--rebase','--autostash','--quiet') $null ([int]([Math]::Min(20, $resto) * 1000))
  }
}

function Format-Attesa([string]$Dir, [string]$Ora, [string]$Per, [DateTime]$Scadenza, [string]$Prima) {
  $w = Wait-Risposta $Dir $Ora $Per $Scadenza
  $log = @(); if ($Prima) { $log += $Prima }
  if ($w.trovata) {
    $log += "RISPOSTA ARRIVATA da $Per. Riporta subito a Federico questa risposta in chat, così com'è e in italiano (non riassumerla, non aggiungere commenti, non dirgli di aprire richieste.md né di usare /grok:risposte):"
    $log += ''
    $log += $w.testo
    return ($log -join "`n")
  }
  if ($w.manca) { $log += "Non trovo in $File la richiesta '## $Ora · $Per · …'. Dillo a Federico in una riga."; return ($log -join "`n") }
  $min = 0
  try { $min = ((Get-RomeNow) - [DateTime]::ParseExact($Ora, 'yyyy-MM-dd HH:mm', [Globalization.CultureInfo]::InvariantCulture)).TotalMinutes } catch {}
  if ($min -gt $MaxAttesaMin) {
    $log += "La risposta di $Per non è ancora arrivata dopo $([int]$min) minuti. Smetti di aspettare e di' a Federico in una riga che $Per non ha ancora risposto e che la richiesta resta aperta in $File."
  } else {
    $log += "IN ATTESA: la risposta di $Per non è ancora arrivata (di solito ci mette 1-3 minuti). Chiama SUBITO lo strumento grok_attendi con per='$Per' e ora='$Ora', e richiamalo ogni volta che risponde così, finché arriva la risposta. Nel frattempo non scrivere niente a Federico e non chiedergli nulla (niente /grok:risposte): quando arriva, riportagliela tu."
  }
  return ($log -join "`n")
}

function Send-Webhook([string]$Per, [string]$Testo) {
  $url = Get-EnvValue 'GROK_WEBHOOK_URL'
  $key = Get-EnvValue 'GROK_WEBHOOK_KEY'
  if (-not $url -or -not $key) { return 'Webhook NON inviato: mancano le variabili GROK_WEBHOOK_URL o GROK_WEBHOOK_KEY su Windows. La richiesta resta in richieste.md e il bot la vede al prossimo controllo.' }
  $payload = @{ per = $Per; file = $File; testo = $Testo } | ConvertTo-Json -Compress
  try {
    $r = Invoke-WebRequest -Uri $url -Method Post -Headers @{ Authorization = "Bearer $key" } `
         -ContentType 'application/json; charset=utf-8' -Body ($Utf8.GetBytes($payload)) -UseBasicParsing -TimeoutSec 30
    return "Webhook inviato a $Per (HTTP $([int]$r.StatusCode))."
  } catch {
    $msg = $_.Exception.Message
    try { $code = [int]$_.Exception.Response.StatusCode; if ($code) { $msg = "HTTP $code" } } catch {}
    # Per sicurezza non ripetiamo mai l'indirizzo del webhook né la chiave.
    $msg = $msg.Replace($url, '<webhook>').Replace($key, '<chiave>')
    return "Webhook NON inviato ($msg). La richiesta resta in richieste.md e il bot la vede al prossimo controllo."
  }
}

function Get-OneLine([string]$S, [int]$Max) {
  $S = ($S -replace '[\r\n\t]+', ' ').Trim()
  if ($S.Length -gt $Max) { $S = $S.Substring(0, $Max).TrimEnd() + '…' }
  return $S
}

function Invoke-GrokInvia($a) {
  $scad = [DateTime]::UtcNow.AddSeconds($AttesaS)
  $r = Resolve-Bot ([string]$a.per); $testo = ([string]$a.testo).Trim()
  if ($null -eq $r) { throw "Manca il destinatario. Bot: $ElencoBot" }
  $per = $r.per
  if (-not $testo) { throw 'Testo della richiesta vuoto.' }
  # Nome non in elenco: la richiesta va a Grok Bot, che la smista al bot giusto.
  if ($r.inoltro) { $testo = "Per: $($r.inoltro) (smista tu al bot giusto)`n$testo" }
  Test-Git
  $dir = Get-RepoDir
  $path = Join-Path $dir $File
  if (-not (Test-Path -LiteralPath $path)) { throw "Non trovo $File in $dir. Clona il repo grok-claude-hub in quella cartella oppure imposta la variabile GROK_HUB_DIR." }

  $g = Invoke-Git $dir @('pull','--rebase','--autostash')
  if (-not $g.ok) { throw "git pull non riuscito, non ho scritto nulla: $($g.text)" }

  # Sezione nel formato di HANDOFF.md, con le stesse terminazioni di riga del file (LF, o CRLF se già così).
  $old = [IO.File]::ReadAllText($path, $Utf8)
  $nl = "`n"; if ($old.Contains("`r`n")) { $nl = "`r`n" }
  $sez = ''
  if ($old.Length -gt 0 -and -not $old.EndsWith("`n")) { $sez += $nl }
  $ora = Get-RomeTime
  $sez += $nl + "## $ora · $per · aperta" + $nl + ($testo -replace "`r?`n", $nl) + $nl
  $f = Get-OneLine ([string]$a.file) 300
  if ($f) { $sez += "File: $f" + $nl }
  [IO.File]::AppendAllText($path, $sez, $Utf8)

  $arg = Get-OneLine ([string]$a.argomento) 60
  if (-not $arg) { $arg = Get-OneLine $testo 60 }
  $null = Invoke-Git $dir @('add', $File)
  # Messaggio di commit passato su stdin: nessun problema di virgolette o accenti sulla riga di comando.
  $c = Invoke-Git $dir @('commit','--quiet','-F','-') "richiesta ${per}: $arg (da Cowork)`n"
  if (-not $c.ok) { throw "git commit non riuscito: $($c.text)" }

  $p = Invoke-Git $dir @('push')
  if (-not $p.ok) {
    $null = Invoke-Git $dir @('pull','--rebase','--autostash')
    $p = Invoke-Git $dir @('push')
  }
  $log = @()
  if ($p.ok) {
    $log += "Richiesta aggiunta in fondo a $File, commit e push fatti."
    $log += (Send-Webhook $per $testo)
    return (Format-Attesa $dir $ora $per $scad ($log -join "`n"))
  } else {
    $log += "Richiesta aggiunta e committata in $File, ma il push NON è riuscito: $($p.text)"
    $log += 'Webhook non inviato (il bot non vedrebbe ancora la richiesta su GitHub). Dillo a Federico in due righe: il prossimo invio spinge anche questo commit. Non aspettare la risposta.'
  }
  return ($log -join "`n")
}

function Invoke-GrokAttendi($a) {
  $scad = [DateTime]::UtcNow.AddSeconds($AttesaS)
  $r = Resolve-Bot ([string]$a.per); if ($null -eq $r) { throw "Manca il destinatario. Bot: $ElencoBot" }
  $per = $r.per
  $ora = ([string]$a.ora).Trim()
  if ($ora -notmatch '^\d{4}-\d{2}-\d{2} \d{2}:\d{2}$') { throw "ora deve essere nel formato AAAA-MM-GG HH:MM, come nel titolo della richiesta (era: '$ora')." }
  Test-Git
  $dir = Get-RepoDir
  if (-not (Test-Path -LiteralPath (Join-Path $dir $File))) { throw "Non trovo $File in $dir." }
  $null = Invoke-Git $dir @('pull','--rebase','--autostash','--quiet') $null 20000
  return (Format-Attesa $dir $ora $per $scad $null)
}

function Invoke-GrokRichieste($a) {
  Test-Git
  $dir = Get-RepoDir
  $path = Join-Path $dir $File
  if (-not (Test-Path -LiteralPath $path)) { throw "Non trovo $File in $dir. Clona il repo grok-claude-hub in quella cartella oppure imposta la variabile GROK_HUB_DIR." }
  $g = Invoke-Git $dir @('pull','--rebase','--autostash')
  $t = [IO.File]::ReadAllText($path, $Utf8)
  if ($t.Length -gt 40000) { $t = "[…inizio del file omesso…]`n" + $t.Substring($t.Length - 40000) }
  $head = 'Repo aggiornato.'
  if (-not $g.ok) { $head = "git pull non riuscito ($($g.text)): mostro la copia locale." }
  return "$head`n`n$t"
}

$Tools = @(
  @{ name = 'grok_invia'
     description = 'Manda una richiesta a un bot Grok Bot di Federico: la aggiunge in fondo a richieste.md del repo grok-claude-hub (ora di Roma), fa commit e push, avvisa il bot via webhook e aspetta la risposta (fino a ~50 s). Se la risposta arriva la restituisce: riportala a Federico così com''è. Se non è ancora arrivata, chiama grok_attendi finché arriva.'
     inputSchema = @{ type = 'object'
       properties = @{
         per = @{ type = 'string'; description = "Bot destinatario: @nome oppure nome completo o alias (es. raimondo, il piccolo raimondo vianello). Bot: $ElencoBot. Un nome non in elenco va comunque inviato: arriva a @grok-bot che lo smista. Non rifiutare mai un nome." }
         testo = @{ type = 'string'; description = 'Testo della richiesta, così come lo ha scritto Federico' }
         file = @{ type = 'string'; description = 'Facoltativo: percorso di un file del repo citato nella richiesta' }
         argomento = @{ type = 'string'; description = 'Facoltativo: argomento in poche parole, per il messaggio di commit' } }
       required = @('per','testo') } },
  @{ name = 'grok_attendi'
     description = 'Aspetta ancora (fino a ~50 s, git pull ogni 10 s) la risposta di un bot a una richiesta già mandata con grok_invia. Chiamalo di nuovo finché la risposta arriva, poi riportala a Federico così com''è. Non chiedere mai a Federico di controllare lui.'
     inputSchema = @{ type = 'object'
       properties = @{
         per = @{ type = 'string'; description = 'Bot restituito da grok_invia (lo stesso @nome del titolo della richiesta)' }
         ora = @{ type = 'string'; description = 'Data e ora della richiesta, AAAA-MM-GG HH:MM, come restituita da grok_invia' } }
       required = @('per','ora') } },
  @{ name = 'grok_richieste'
     description = 'Aggiorna il repo grok-claude-hub (git pull) e restituisce il contenuto di richieste.md, con le richieste ai bot e le loro risposte.'
     inputSchema = @{ type = 'object'; properties = @{} } }
)
$Istruzioni = 'Connettore grok-hub: usa grok_invia per mandare una richiesta a un bot Grok Bot di Federico (scrive in richieste.md del repo grok-claude-hub, fa push, avvisa il bot e aspetta la risposta). Se la risposta non è ancora arrivata, chiama grok_attendi finché arriva, poi riportala a Federico in chat così com''è. Non dire mai a Federico di usare /grok:risposte o di controllare lui. grok_richieste mostra tutte le richieste. Rispondi in italiano. Bot disponibili: ' + $ElencoBot + '. Se Federico nomina un bot che non è in elenco, manda comunque con grok_invia: arriva a @grok-bot che lo smista; non dire mai che un bot non esiste.'

function Send-Msg($obj) { $Out.WriteLine(($obj | ConvertTo-Json -Depth 20 -Compress)) }
function Send-Result($id, $result) { Send-Msg @{ jsonrpc = '2.0'; id = $id; result = $result } }
function Send-Error($id, [int]$code, [string]$message) { Send-Msg @{ jsonrpc = '2.0'; id = $id; error = @{ code = $code; message = $message } } }

Write-Log "avviato (repo: $(Get-RepoDir))"
while ($true) {
  $line = $In.ReadLine()
  if ($null -eq $line) { break }
  if (-not $line.Trim()) { continue }
  try { $req = $line | ConvertFrom-Json } catch { Write-Log 'riga non JSON ignorata'; continue }
  $names = @($req.PSObject.Properties.Name)
  if ($names -notcontains 'id') { continue }        # notifiche: nessuna risposta
  if ($names -notcontains 'method') { continue }    # risposte del client: nessuna risposta
  $id = $req.id
  try {
    switch ($req.method) {
      'initialize' {
        $v = '2025-06-18'
        if ($req.params -and $req.params.protocolVersion -and ($Versioni -contains [string]$req.params.protocolVersion)) { $v = [string]$req.params.protocolVersion }
        Send-Result $id @{ protocolVersion = $v; capabilities = @{ tools = @{} }; serverInfo = @{ name = 'grok-hub'; version = '1.3.1' }; instructions = $Istruzioni }
      }
      'ping' { Send-Result $id @{} }
      'tools/list' { Send-Result $id @{ tools = $Tools } }
      'tools/call' {
        $n = [string]$req.params.name; $a = $req.params.arguments
        if ($null -eq $a) { $a = New-Object PSObject }
        Write-Log "tools/call $n"
        $ProgressToken = $null
        try { if ($req.params._meta -and $null -ne $req.params._meta.progressToken) { $ProgressToken = $req.params._meta.progressToken } } catch {}
        try {
          if ($n -eq 'grok_invia') { $txt = Invoke-GrokInvia $a }
          elseif ($n -eq 'grok_attendi') { $txt = Invoke-GrokAttendi $a }
          elseif ($n -eq 'grok_richieste') { $txt = Invoke-GrokRichieste $a }
          else { throw "Strumento sconosciuto: $n" }
          Send-Result $id @{ content = @(@{ type = 'text'; text = [string]$txt }); isError = $false }
        } catch {
          Write-Log "errore in $n : $($_.Exception.Message)"
          Send-Result $id @{ content = @(@{ type = 'text'; text = "Errore: $($_.Exception.Message)" }); isError = $true }
        }
      }
      default { Send-Error $id -32601 "Metodo non supportato: $($req.method)" }
    }
  } catch {
    Write-Log "errore interno: $($_.Exception.Message)"
    try { Send-Error $id -32603 $_.Exception.Message } catch {}
  }
}
$Out.Flush()
