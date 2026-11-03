$ErrorActionPreference = 'Stop'
$root = [IO.Path]::GetFullPath((Join-Path $PSScriptRoot '../assets/workbench'))
$headers = @{ 'User-Agent' = 'WeaveAndWander-ArtPrototype/1.0' }
$records = @()

function Fetch-AssetFile($entry, $destination) {
    New-Item -ItemType Directory -Force -Path (Split-Path $destination) | Out-Null
    if (!(Test-Path -LiteralPath $destination) -or (Get-FileHash -LiteralPath $destination -Algorithm MD5).Hash.ToLower() -ne $entry.md5) {
        Invoke-WebRequest -Uri $entry.url -OutFile $destination -Headers $headers
    }
    if ((Get-FileHash -LiteralPath $destination -Algorithm MD5).Hash.ToLower() -ne $entry.md5) { throw "Checksum mismatch: $destination" }
    Write-Output "Verified $destination"
}

foreach ($asset in @(@{id='black_walnut_veneer_02'; resolution='2k'}, @{id='rough_linen'; resolution='1k'}, @{id='white_plaster_02'; resolution='1k'})) {
    $id = $asset.id
    $info = Invoke-RestMethod "https://api.polyhaven.com/info/$id" -Headers $headers
    $files = Invoke-RestMethod "https://api.polyhaven.com/files/$id" -Headers $headers
    $downloads = @()
    foreach ($map in @('Diffuse','nor_gl','Rough')) {
        $entry = $files.$map.($asset.resolution).jpg
        if (!$entry) { throw "Missing $id $map" }
        $filename = [IO.Path]::GetFileName(([uri]$entry.url).AbsolutePath)
        Fetch-AssetFile $entry (Join-Path $root "textures/$filename")
        $downloads += @{file="textures/$filename"; url=$entry.url; md5=$entry.md5}
    }
    $records += @{id=$id; name=$info.name; authors=$info.authors; source="https://polyhaven.com/a/$id"; license='CC0-1.0'; files=$downloads}
}

foreach ($id in @('potted_plant_02','desk_lamp_arm_01','wicker_basket_02','book_encyclopedia_set_01','jacaranda_tree','fern_02')) {
    $info = Invoke-RestMethod "https://api.polyhaven.com/info/$id" -Headers $headers
    $files = Invoke-RestMethod "https://api.polyhaven.com/files/$id" -Headers $headers
    $entry = $files.gltf.'1k'.gltf
    $downloads = @()
    $filename = [IO.Path]::GetFileName(([uri]$entry.url).AbsolutePath)
    Fetch-AssetFile $entry (Join-Path $root "$id/$filename")
    $downloads += @{file="$id/$filename"; url=$entry.url; md5=$entry.md5}
    foreach ($part in $entry.include.PSObject.Properties) {
        Fetch-AssetFile $part.Value (Join-Path $root "$id/$($part.Name)")
        $downloads += @{file="$id/$($part.Name)"; url=$part.Value.url; md5=$part.Value.md5}
    }
    $records += @{id=$id; name=$info.name; authors=$info.authors; source="https://polyhaven.com/a/$id"; license='CC0-1.0'; files=$downloads}
}
$records | ConvertTo-Json -Depth 9 | Set-Content -LiteralPath (Join-Path $root 'sources.json') -Encoding utf8
