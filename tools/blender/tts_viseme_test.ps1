# Verify Windows SAPI can (a) synthesize to WAV headless and (b) emit viseme
# events with audio-offset timing -> the lip-sync data source.
Add-Type -AssemblyName System.Speech
$outDir = "C:\Users\kevin\game-studio\tools\blender\voice"
New-Item -ItemType Directory -Force -Path $outDir | Out-Null
$wav = Join-Path $outDir "test.wav"

$global:vis = New-Object System.Collections.ArrayList
$s = New-Object System.Speech.Synthesis.SpeechSynthesizer

# direct delegate -> fires synchronously during Speak (reliable capture)
$s.add_VisemeReached({
    param($snd, $e)
    [void]$global:vis.Add([pscustomobject]@{
        ms     = [int]$e.Audio.TotalMilliseconds
        viseme = [int]$e.Viseme
        dur    = [int]$e.Duration.TotalMilliseconds
    })
})

Write-Output "Voices available:"
$s.GetInstalledVoices() | ForEach-Object { "  - " + $_.VoiceInfo.Name + " (" + $_.VoiceInfo.Culture + ")" }

$s.Rate = 0
$s.SetOutputToWaveFile($wav)
$s.Speak("Testing one two three. The quick brown fox jumps.")
$s.SetOutputToNull()
$s.Dispose()

Write-Output ("WAV exists: " + (Test-Path $wav) + "  size: " + (Get-Item $wav).Length + " bytes")
Write-Output ("Viseme events captured: " + $global:vis.Count)
Write-Output "First 15 (ms, visemeID, durMs):"
$global:vis | Select-Object -First 15 | ForEach-Object { "  {0,5}  v{1,-2}  {2}ms" -f $_.ms, $_.viseme, $_.dur }
$last = $global:vis[$global:vis.Count-1]
Write-Output ("Last event ends ~" + ($last.ms + $last.dur) + "ms")
