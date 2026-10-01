<?php

header("Access-Control-Allow-Origin: *");
header("Access-Control-Allow-Methods: GET, POST, OPTIONS");
header("Access-Control-Allow-Headers: Content-Type");
header("Connection: close");
header("Content-Type: application/json");

$ytdlp = 'C:\\Users\\Administrator\\AppData\\Local\\Packages\\PythonSoftwareFoundation.Python.3.13_qbz5n2kfra8p0\\LocalCache\\local-packages\\Python313\\Scripts\\yt-dlp.exe';
$ffmpeg = 'C:\\Users\\Administrator\\AppData\\Local\\Microsoft\\WinGet\\Links\\ffmpeg.exe';
$downloadsDir = __DIR__ . '/downloads';

if (!is_dir($downloadsDir)) {
    mkdir($downloadsDir, 0777, true);
}

function executeCliCommand($cmd) {
    return shell_exec($cmd);
}

function getYtDlpVersion($ytdlp) {
    static $cachedVersion = null;
    if ($cachedVersion !== null) return $cachedVersion;
    $verFile = sys_get_temp_dir() . '/ytdlp_version.cache';
    if (file_exists($verFile) && (time() - filemtime($verFile) < 3600)) {
        $cachedVersion = trim(file_get_contents($verFile));
        return $cachedVersion;
    }
    $cmd = escapeshellarg($ytdlp) . ' --version 2> NUL';
    $cachedVersion = trim(executeCliCommand($cmd) ?? '2026.08.19');
    @file_put_contents($verFile, $cachedVersion);
    return $cachedVersion;
}

$path = $_SERVER['PATH_INFO'] ?? '/';

// Serve HTML app if requested via browser at root
if ($path === '/' || $path === '') {
    $accept = $_SERVER['HTTP_ACCEPT'] ?? '';
    if (strpos($accept, 'text/html') !== false && !isset($_GET['json']) && file_exists(__DIR__ . '/index.html')) {
        header("Content-Type: text/html; charset=utf-8");
        readfile(__DIR__ . '/index.html');
        exit;
    }

    $version = getYtDlpVersion($ytdlp);
    echo json_encode([
        'api'    => 'Fast YouTube Downloader Backend (Core PHP)',
        'yt_dlp' => $version ?: 'not found',
        'php'    => PHP_VERSION,
        'status' => 'online',
    ]);
    exit;
}

if ($path === '/api/status') {
    $version = getYtDlpVersion($ytdlp);
    $ffmpegOk = file_exists($ffmpeg);
    echo json_encode([
        'api'      => 'Fast YouTube Downloader Backend (Core PHP)',
        'yt_dlp'   => $version ?: 'not found',
        'php'      => PHP_VERSION,
        'ffmpeg'   => $ffmpegOk ? 'installed' : 'missing',
        'status'   => 'online',
    ]);
    exit;
}

if ($path === '/api/formats') {
    $rawInput = json_decode(file_get_contents('php://input'), true);
    $url = $_GET['url'] ?? $_POST['url'] ?? ($rawInput['url'] ?? '');
    if (empty($url)) {
        http_response_code(422);
        echo json_encode(['success' => false, 'error' => 'URL is required.']);
        exit;
    }

    if (!preg_match('/youtube\.com|youtu\.be/', $url)) {
        http_response_code(422);
        echo json_encode(['success' => false, 'error' => 'Only YouTube URLs are supported.']);
        exit;
    }

    $safeUrl = escapeshellarg($url);
    $cmd = escapeshellarg($ytdlp) . " -J --no-playlist --no-warnings --no-update --js-runtimes node --socket-timeout 10 $safeUrl 2> NUL";
    $output = executeCliCommand($cmd);

    if (!$output) {
        http_response_code(500);
        echo json_encode(['success' => false, 'error' => 'yt-dlp returned no output.']);
        exit;
    }

    $info = json_decode($output, true);
    if (json_last_error() !== JSON_ERROR_NONE || empty($info['formats'])) {
        http_response_code(500);
        echo json_encode(['success' => false, 'error' => 'Could not parse video details.']);
        exit;
    }

    $videoTitle = $info['title'] ?? 'YouTube_Video';
    $formatsMap = [];
    $bestAudio = null;
    $allowedHeights = [144, 240, 360, 480, 720, 1080, 1440, 2160];

    $duration = $info['duration'] ?? 0;

    foreach ($info['formats'] as $f) {
        $vcodec = $f['vcodec'] ?? 'none';
        $acodec = $f['acodec'] ?? 'none';
        $height = $f['height'] ?? null;
        $abr    = $f['abr'] ?? 0;
        $tbr    = $f['tbr'] ?? 0;
        $vbr    = $f['vbr'] ?? 0;
        $ext    = $f['ext'] ?? 'mp4';
        $fid    = $f['format_id'];

        $filesize = $f['filesize'] ?? $f['filesize_approx'] ?? null;
        if (!$filesize && $duration > 0) {
            $effectiveBitrate = $tbr ?: ($vbr + ($abr ?: 128));
            if ($effectiveBitrate > 0) {
                // effectiveBitrate is in kbps, duration in seconds -> bytes
                $filesize = (int)round(($effectiveBitrate * 1000 / 8) * $duration);
            }
        }

        if ($vcodec !== 'none' && $height && in_array($height, $allowedHeights)) {
            $hasAudio = ($acodec !== 'none');
            $ext = $ext === 'webm' ? 'mp4' : $ext; 
            
            $formatIdToSend = $fid;
            if (!$hasAudio) {
                $formatIdToSend .= '+bestaudio';
            }

            if (!isset($formatsMap[$height]) || $hasAudio) {
                // Determine base URL dynamically
                $protocol = isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? "https" : "http";
                $host = $_SERVER['HTTP_HOST'];
                $baseUrl = "$protocol://$host" . str_replace('/index.php', '', $_SERVER['SCRIPT_NAME']);
                
                $formatsMap[$height] = [
                    'label'        => "{$height}p Video+Audio ($ext)",
                    'type'         => 'video',
                    'height'       => $height,
                    'ext'          => $ext,
                    'filesize'     => $filesize,
                    'download_url' => $baseUrl . "/api/download?url=" . urlencode($url) . "&format_id=" . urlencode($formatIdToSend) . "&title=" . urlencode($videoTitle),
                ];
            }
        }
        elseif ($vcodec === 'none' && $acodec !== 'none') {
            if (!$bestAudio || $abr > $bestAudio['abr']) {
                $protocol = isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? "https" : "http";
                $host = $_SERVER['HTTP_HOST'];
                $baseUrl = "$protocol://$host" . str_replace('/index.php', '', $_SERVER['SCRIPT_NAME']);

                $bestAudio = [
                    'label'        => "High Quality MP3 Audio (" . round($abr) . "kbps)",
                    'type'         => 'audio',
                    'height'       => 0,
                    'abr'          => $abr,
                    'ext'          => 'mp3', 
                    'filesize'     => $filesize,
                    'download_url' => $baseUrl . "/api/download?url=" . urlencode($url) . "&format_id=" . urlencode($fid) . "&type=audio&ext=mp3&title=" . urlencode($videoTitle),
                ];
            }
        }
    }

    $formats = array_values($formatsMap);
    if ($bestAudio) {
        $formats[] = $bestAudio;
    }

    usort($formats, fn($a, $b) => $b['height'] - $a['height']);

    if (empty($formats)) {
        http_response_code(404);
        echo json_encode(['success' => false, 'error' => 'No formats found.']);
        exit;
    }

    echo json_encode([
        'success'   => true,
        'title'     => $videoTitle,
        'thumbnail' => $info['thumbnail'] ?? '',
        'duration'  => $info['duration'] ?? 0,
        'formats'   => $formats,
    ]);
    exit;
}

if ($path === '/api/prepare') {
    @set_time_limit(600);
    $rawInput = json_decode(file_get_contents('php://input'), true);
    $url      = $_GET['url'] ?? $_POST['url'] ?? ($rawInput['url'] ?? '');
    $formatId = $_GET['format_id'] ?? $_POST['format_id'] ?? ($rawInput['format_id'] ?? '');
    $title    = $_GET['title'] ?? $_POST['title'] ?? ($rawInput['title'] ?? 'YouTube_Media');

    if (empty($url) || empty($formatId)) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Missing url or format_id.']);
        exit;
    }

    $isAudio = (isset($_GET['type']) && $_GET['type'] === 'audio') || 
               (isset($_GET['ext']) && $_GET['ext'] === 'mp3') || 
               in_array($formatId, ['140', '251', '139', '249', 'ba', 'bestaudio']);
               
    $ext = $isAudio ? 'mp3' : 'mp4';

    // Clean title for safe filesystem & download filename
    $cleanTitle = preg_replace('/[^\w\s\-\.\(\)]/u', '_', $title);
    $cleanTitle = trim(preg_replace('/\s+/', ' ', $cleanTitle));
    if (empty($cleanTitle)) $cleanTitle = 'YouTube_Media';

    // Strip playlist parameters so yt-dlp only downloads single video
    $cleanUrl = preg_replace('/&list=[^&]+/', '', $url);
    $cleanUrl = preg_replace('/&index=[^&]+/', '', $cleanUrl);
    $cleanUrl = preg_replace('/&start_radio=[^&]+/', '', $cleanUrl);

    // Unique local cached filename
    $safeHash = md5($cleanUrl . '_' . $formatId . '_' . $ext);
    $localFileName = "dl_{$safeHash}.{$ext}";
    $absolutePath = $downloadsDir . DIRECTORY_SEPARATOR . $localFileName;

    $safeUrl = escapeshellarg($cleanUrl);
    $safeFmt = escapeshellarg($formatId);

    // If file does not exist on server yet, download and process it with yt-dlp + ffmpeg
    $cmdOutput = '';
    if (!file_exists($absolutePath) || filesize($absolutePath) === 0) {
        if ($isAudio) {
            $cmd = escapeshellarg($ytdlp) . " --no-playlist -f \"ba/b\" -x --audio-format mp3 --audio-quality 0 --ffmpeg-location " . escapeshellarg($ffmpeg) . " --js-runtimes node --no-warnings --no-update -o " . escapeshellarg($absolutePath) . " $safeUrl 2>&1";
        } else {
            $cmd = escapeshellarg($ytdlp) . " --no-playlist -f $safeFmt --ffmpeg-location " . escapeshellarg($ffmpeg) . " --merge-output-format mp4 --js-runtimes node --no-warnings --no-update -o " . escapeshellarg($absolutePath) . " $safeUrl 2>&1";
        }
        $cmdOutput = executeCliCommand($cmd);
    }

    if (!file_exists($absolutePath) || filesize($absolutePath) === 0) {
        http_response_code(500);
        echo json_encode([
            'success' => false, 
            'error'   => 'Failed to process media file with yt-dlp/ffmpeg.',
            'details' => $cmdOutput ?: 'No output from command'
        ]);
        exit;
    }

    $protocol = isset($_SERVER['HTTPS']) && $_SERVER['HTTPS'] === 'on' ? "https" : "http";
    $host = $_SERVER['HTTP_HOST'];
    $baseUrl = "$protocol://$host" . str_replace('/index.php', '', $_SERVER['SCRIPT_NAME']);
    $readyUrl = $baseUrl . "/api/download?file=" . urlencode($localFileName) . "&title=" . urlencode($cleanTitle) . "&ext=" . $ext;

    echo json_encode([
        'success'      => true,
        'ready'        => true,
        'file_name'    => "{$cleanTitle}.{$ext}",
        'size_bytes'   => filesize($absolutePath),
        'download_url' => $readyUrl
    ]);
    exit;
}

if ($path === '/api/download') {
    @set_time_limit(600); // 10 minutes max for high-res merges

    // Instant download for prepared/cached files by filename
    if (!empty($_GET['file'])) {
        $fileName = basename($_GET['file']);
        $filePath = $downloadsDir . DIRECTORY_SEPARATOR . $fileName;
        if (file_exists($filePath) && filesize($filePath) > 0) {
            $title = $_GET['title'] ?? 'YouTube_Media';
            $ext = $_GET['ext'] ?? pathinfo($fileName, PATHINFO_EXTENSION);
            $cleanTitle = preg_replace('/[^\w\s\-\.\(\)]/u', '_', $title);
            $cleanTitle = trim(preg_replace('/\s+/', ' ', $cleanTitle)) ?: 'YouTube_Media';
            $outputName = "{$cleanTitle}.{$ext}";

            while (ob_get_level()) { ob_end_clean(); }
            header("Content-Description: File Transfer");
            header("Content-Type: application/octet-stream");
            header("Content-Disposition: attachment; filename=\"" . addslashes($outputName) . "\"; filename*=UTF-8''" . rawurlencode($outputName));
            header("Content-Transfer-Encoding: binary");
            header("Expires: 0");
            header("Cache-Control: must-revalidate, post-check=0, pre-check=0");
            header("Pragma: public");
            header("Content-Length: " . filesize($filePath));
            readfile($filePath);
            exit;
        }
    }

    $url      = $_GET['url'] ?? '';
    $formatId = $_GET['format_id'] ?? '';
    $title    = $_GET['title'] ?? 'YouTube_Media';
    $isStream = isset($_GET['stream']) && $_GET['stream'] === '1';

    if (empty($url) || empty($formatId)) {
        http_response_code(400);
        echo json_encode(['success' => false, 'error' => 'Missing url or format_id.']);
        exit;
    }

    $isAudio = (isset($_GET['type']) && $_GET['type'] === 'audio') || 
               (isset($_GET['ext']) && $_GET['ext'] === 'mp3') || 
               in_array($formatId, ['140', '251', '139', '249', 'ba', 'bestaudio']);
               
    $ext = $isAudio ? 'mp3' : 'mp4';

    // Clean title for safe filesystem & download filename
    $cleanTitle = preg_replace('/[^\w\s\-\.\(\)]/u', '_', $title);
    $cleanTitle = trim(preg_replace('/\s+/', ' ', $cleanTitle));
    if (empty($cleanTitle)) $cleanTitle = 'YouTube_Media';
    $downloadOutputName = "{$cleanTitle}.{$ext}";

    // Strip playlist parameters
    $cleanUrl = preg_replace('/&list=[^&]+/', '', $url);
    $cleanUrl = preg_replace('/&index=[^&]+/', '', $cleanUrl);
    $cleanUrl = preg_replace('/&start_radio=[^&]+/', '', $cleanUrl);

    // Unique local cached filename
    $safeHash = md5($cleanUrl . '_' . $formatId . '_' . $ext);
    $localFileName = "dl_{$safeHash}.{$ext}";
    $absolutePath = $downloadsDir . DIRECTORY_SEPARATOR . $localFileName;

    $safeUrl = escapeshellarg($cleanUrl);
    $safeFmt = escapeshellarg($formatId);

    // If file does not exist on server yet, download and process it with yt-dlp + ffmpeg
    $cmdOutput = '';
    if (!file_exists($absolutePath) || filesize($absolutePath) === 0) {
        if ($isAudio) {
            $cmd = escapeshellarg($ytdlp) . " --no-playlist -f \"ba/b\" -x --audio-format mp3 --audio-quality 0 --ffmpeg-location " . escapeshellarg($ffmpeg) . " --js-runtimes node --no-warnings --no-update -o " . escapeshellarg($absolutePath) . " $safeUrl 2>&1";
        } else {
            $cmd = escapeshellarg($ytdlp) . " --no-playlist -f $safeFmt --ffmpeg-location " . escapeshellarg($ffmpeg) . " --merge-output-format mp4 --js-runtimes node --no-warnings --no-update -o " . escapeshellarg($absolutePath) . " $safeUrl 2>&1";
        }
        $cmdOutput = executeCliCommand($cmd);
    }

    if (!file_exists($absolutePath) || filesize($absolutePath) === 0) {
        http_response_code(500);
        echo json_encode([
            'success' => false, 
            'error'   => 'Failed to process and save media file.',
            'cmd'     => $cmd ?? '',
            'details' => $cmdOutput ?: 'No output from command'
        ]);
        exit;
    }

    while (ob_get_level()) { ob_end_clean(); }

    if ($isStream) {
        $mime = $isAudio ? "audio/mpeg" : "video/mp4";
        header("Content-Type: $mime");
        header("Content-Length: " . filesize($absolutePath));
        readfile($absolutePath);
        exit;
    }

    header("Content-Description: File Transfer");
    header("Content-Type: application/octet-stream");
    header("Content-Disposition: attachment; filename=\"" . addslashes($downloadOutputName) . "\"; filename*=UTF-8''" . rawurlencode($downloadOutputName));
    header("Content-Transfer-Encoding: binary");
    header("Expires: 0");
    header("Cache-Control: must-revalidate, post-check=0, pre-check=0");
    header("Pragma: public");
    header("Content-Length: " . filesize($absolutePath));
    readfile($absolutePath);
    exit;
}

// Serve files from downloads directory if requested
if (strpos($path, '/downloads/') === 0) {
    $fileName = basename($path);
    $filePath = $downloadsDir . '/' . $fileName;
    if (file_exists($filePath)) {
        header("Content-Type: application/octet-stream");
        header("Content-Disposition: attachment; filename=\"$fileName\"");
        readfile($filePath);
        exit;
    } else {
        http_response_code(404);
        echo json_encode(['success' => false, 'error' => 'File not found.']);
        exit;
    }
}

http_response_code(404);
echo json_encode(['success' => false, 'error' => 'Endpoint not found.']);
