param([string]$Path, [string]$OutFile)
$bytes = [IO.File]::ReadAllBytes($Path)
$lat = [Text.Encoding]::GetEncoding(28591)
$s = $lat.GetString($bytes)
$streams = New-Object System.Collections.ArrayList
foreach ($m in [regex]::Matches($s,'stream\r?\n')) {
  $start = $m.Index + $m.Length
  $end = $s.IndexOf('endstream',$start)
  if ($end -lt 0) { continue }
  $chunk = $bytes[$start..($end-1)]
  try {
    $ms2 = New-Object IO.MemoryStream(,$chunk[2..($chunk.Length-1)])
    $ds = New-Object IO.Compression.DeflateStream($ms2,[IO.Compression.CompressionMode]::Decompress)
    $rd = New-Object IO.MemoryStream; $ds.CopyTo($rd)
    [void]$streams.Add($lat.GetString($rd.ToArray()))
  } catch {}
}
function Parse-CMap($t) {
  $d = @{}
  foreach ($blk in [regex]::Matches($t,'beginbfchar(.*?)endbfchar','Singleline')) {
    foreach ($m in [regex]::Matches($blk.Groups[1].Value,'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>')) {
      $d[[Convert]::ToInt32($m.Groups[1].Value,16)] = [char][Convert]::ToInt32($m.Groups[2].Value,16)
    }
  }
  foreach ($blk in [regex]::Matches($t,'beginbfrange(.*?)endbfrange','Singleline')) {
    foreach ($m in [regex]::Matches($blk.Groups[1].Value,'<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>\s*<([0-9A-Fa-f]+)>')) {
      $a=[Convert]::ToInt32($m.Groups[1].Value,16); $b=[Convert]::ToInt32($m.Groups[2].Value,16); $u=[Convert]::ToInt32($m.Groups[3].Value,16)
      for ($i=$a; $i -le $b; $i++) { $d[$i] = [char]($u + $i - $a) }
    }
  }
  return $d
}
$cmaps = @($streams | Where-Object { $_ -match 'beginbfchar|beginbfrange' } | ForEach-Object { Parse-CMap $_ })
function Decode($hex, $fontIdx) {
  $sb = New-Object Text.StringBuilder
  for ($i=0; $i -lt $hex.Length; $i+=4) {
    $code = [Convert]::ToInt32($hex.Substring($i,4),16)
    $ch = $null
    foreach ($ix in @($fontIdx) + (0..($cmaps.Count-1))) { if ($cmaps[$ix].ContainsKey($code)) { $ch = $cmaps[$ix][$code]; break } }
    if ($ch -eq $null) { [void]$sb.Append('?') } else { [void]$sb.Append($ch) }
  }
  return $sb.ToString()
}
$result = New-Object System.Collections.ArrayList
$page = 0
foreach ($c in $streams) {
  if ($c -notmatch '\bTj\b' -or $c.Length -lt 1000) { continue }
  $page++
  $runs = New-Object System.Collections.ArrayList
  foreach ($bt in [regex]::Matches($c,'BT(.*?)ET','Singleline')) {
    $body = $bt.Groups[1].Value
    $fontIdx = 0
    if ($body -match '/F1\s') { $fontIdx = 1 }
    $x=0.0; $y=0.0; $txt=''
    foreach ($tok in [regex]::Matches($body,'([-\d\.]+)\s+([-\d\.]+)\s+Td|<([0-9A-Fa-f]+)>\s*Tj')) {
      if ($tok.Groups[3].Success) { $txt += (Decode $tok.Groups[3].Value $fontIdx) }
      else { $x += [double]$tok.Groups[1].Value; $y += [double]$tok.Groups[2].Value }
    }
    if ($txt) { [void]$runs.Add([pscustomobject]@{Page=$page;X=$x;Y=[math]::Round($y);T=$txt}) }
  }
  [void]$result.AddRange(@($runs))
}
$lines = foreach ($grp in ($result | Group-Object Page, Y)) {
  $first = $grp.Group[0]
  "P{0} y={1}: {2}" -f $first.Page, $first.Y, (($grp.Group | Sort-Object X | ForEach-Object { $_.T }) -join ' | ')
}
$lines | Set-Content $OutFile -Encoding utf8
"Pages: $page  Lines: $($lines.Count)"
