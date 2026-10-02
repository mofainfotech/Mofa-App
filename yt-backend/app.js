/**
 * PulseTube - YouTube Downloader & Streamer Client
 * Connects to PHP backend (Core PHP + yt-dlp + FFmpeg)
 */

document.addEventListener('DOMContentLoaded', () => {
  // DOM Elements
  const serverStatusPill   = document.getElementById('serverStatusPill');
  const statusDot          = document.getElementById('statusDot');
  const statusText         = document.getElementById('statusText');
  const systemBadges       = document.getElementById('systemBadges');
  const badgeYtDlp         = document.getElementById('badgeYtDlp');
  const badgePhp           = document.getElementById('badgePhp');
  const badgeFfmpeg        = document.getElementById('badgeFfmpeg');
  const btnRefreshStatus   = document.getElementById('btnRefreshStatus');
  const footerPhpVer       = document.getElementById('footerPhpVer');
  const footerYtDlpVer     = document.getElementById('footerYtDlpVer');

  const searchForm         = document.getElementById('searchForm');
  const videoUrlInput      = document.getElementById('videoUrlInput');
  const btnPasteClipboard  = document.getElementById('btnPasteClipboard');
  const btnClearInput      = document.getElementById('btnClearInput');
  const btnFetch           = document.getElementById('btnFetch');
  const sampleChips        = document.querySelectorAll('.sample-chip');

  const loadingStateCard   = document.getElementById('loadingStateCard');
  const errorAlertCard     = document.getElementById('errorAlertCard');
  const errorTitle         = document.getElementById('errorTitle');
  const errorMessage       = document.getElementById('errorMessage');
  const btnDismissError    = document.getElementById('btnDismissError');

  const resultsSection     = document.getElementById('resultsSection');
  const videoThumbnail     = document.getElementById('videoThumbnail');
  const videoDurationBadge = document.getElementById('videoDurationBadge');
  const videoTitle         = document.getElementById('videoTitle');
  const videoMaxQualityTag = document.getElementById('videoMaxQualityTag');
  const videoFormatCount   = document.getElementById('videoFormatCount');
  const videoStatDuration  = document.getElementById('videoStatDuration');
  const videoSourceLink    = document.getElementById('videoSourceLink');
  const btnCopyTitle       = document.getElementById('btnCopyTitle');
  const btnCopyUrl         = document.getElementById('btnCopyUrl');
  const btnPreviewModalThumb = document.getElementById('btnPreviewModalThumb');

  const formatsGrid        = document.getElementById('formatsGrid');
  const tabsNav            = document.getElementById('formatsTabsNav');
  const countAll           = document.getElementById('countAll');
  const countVideo         = document.getElementById('countVideo');
  const countAudio         = document.getElementById('countAudio');

  const downloadStatusBanner = document.getElementById('downloadStatusBanner');
  const bannerTitle        = document.getElementById('bannerTitle');
  const bannerSubtitle     = document.getElementById('bannerSubtitle');
  const btnCloseBanner     = document.getElementById('btnCloseBanner');

  const historyList        = document.getElementById('historyList');
  const historyEmpty       = document.getElementById('historyEmpty');
  const btnClearHistory    = document.getElementById('btnClearHistory');

  const apiDocsToggle      = document.getElementById('apiDocsToggle');
  const apiDocsBody        = document.getElementById('apiDocsBody');

  const previewModal       = document.getElementById('previewModal');
  const previewModalTitle  = document.getElementById('previewModalTitle');
  const mediaContainer     = document.getElementById('mediaContainer');
  const btnClosePreviewModal = document.getElementById('btnClosePreviewModal');
  const btnCloseModalBtn   = document.getElementById('btnCloseModalBtn');
  const btnModalDirectDownload = document.getElementById('btnModalDirectDownload');
  const toastContainer     = document.getElementById('toastContainer');

  // Application State
  let currentVideoData = null;
  let currentFilter = 'all';
  let isFetching = false;
  const STORAGE_KEY = 'pulsetube_history_v1';

  // --------------------------------------------------------------------------
  // Initialization
  // --------------------------------------------------------------------------
  init();

  function init() {
    checkServerStatus();
    renderHistory();
    attachEventListeners();
  }

  // --------------------------------------------------------------------------
  // Server Status & Health Check
  // --------------------------------------------------------------------------
  async function checkServerStatus() {
    statusDot.className = 'status-indicator-dot';
    statusText.textContent = 'Checking server...';

    try {
      const response = await fetch('/api/status', {
        headers: { 'Accept': 'application/json' }
      });

      if (!response.ok) throw new Error(`HTTP ${response.status}`);

      const data = await response.json();
      statusDot.className = 'status-indicator-dot online';
      statusText.textContent = 'Backend Online';

      if (data.yt_dlp) {
        badgeYtDlp.textContent = `yt-dlp ${data.yt_dlp}`;
        footerYtDlpVer.textContent = data.yt_dlp;
      }
      if (data.python) {
        badgePhp.textContent = `Python ${data.python}`;
        footerPhpVer.textContent = `Python ${data.python}`;
      } else if (data.php) {
        badgePhp.textContent = `${data.php}`;
        footerPhpVer.textContent = data.php;
      }
      if (data.ffmpeg) {
        badgeFfmpeg.textContent = `FFmpeg: ${data.ffmpeg}`;
      }

      systemBadges.style.display = 'flex';
    } catch (err) {
      console.warn('Status check failed:', err);
      statusDot.className = 'status-indicator-dot offline';
      statusText.textContent = 'Backend Offline';
      systemBadges.style.display = 'none';
    }
  }

  // --------------------------------------------------------------------------
  // Format Extraction
  // --------------------------------------------------------------------------
  async function fetchVideoFormats(url) {
    if (!url || !url.trim()) {
      showToast('Please enter a YouTube video URL.', 'error');
      videoUrlInput.focus();
      return;
    }

    url = url.trim();
    if (!url.includes('youtube.com') && !url.includes('youtu.be')) {
      showToast('Only YouTube URLs are supported (e.g. youtube.com or youtu.be).', 'error');
      videoUrlInput.focus();
      return;
    }

    if (isFetching) return;
    setFetchingState(true);
    hideError();
    resultsSection.style.display = 'none';

    try {
      const response = await fetch(`/api/formats?url=${encodeURIComponent(url)}`, {
        headers: { 'Accept': 'application/json' }
      });

      const data = await response.json();

      if (!response.ok || !data.success) {
        throw new Error(data.error || 'Failed to extract video details.');
      }

      currentVideoData = { ...data, sourceUrl: url };
      displayVideoResults(currentVideoData);
      saveToHistory(currentVideoData);
      showToast(`Loaded ${data.formats.length} formats for "${data.title}"`, 'success');
    } catch (err) {
      console.error('Fetch error:', err);
      showError('Extraction Failed', err.message || 'Could not fetch video formats from backend.');
    } finally {
      setFetchingState(false);
    }
  }

  function setFetchingState(loading) {
    isFetching = loading;
    const btnContent = btnFetch.querySelector('.btn-content');
    const btnLoader = btnFetch.querySelector('.btn-loader');

    if (loading) {
      btnFetch.disabled = true;
      btnContent.style.display = 'none';
      btnLoader.style.display = 'inline-flex';
      loadingStateCard.style.display = 'block';
    } else {
      btnFetch.disabled = false;
      btnContent.style.display = 'inline-flex';
      btnLoader.style.display = 'none';
      loadingStateCard.style.display = 'none';
    }
  }

  // --------------------------------------------------------------------------
  // Render Video Showcase & Formats
  // --------------------------------------------------------------------------
  function displayVideoResults(data) {
    videoThumbnail.src = data.thumbnail || '';
    videoThumbnail.alt = data.title || 'YouTube Video Thumbnail';
    videoDurationBadge.textContent = formatDuration(data.duration);
    videoTitle.textContent = data.title || 'Unknown Title';
    videoStatDuration.textContent = formatDurationDetailed(data.duration);
    videoSourceLink.href = data.sourceUrl;
    videoFormatCount.textContent = `${data.formats ? data.formats.length : 0} Formats`;

    // Max quality determination
    const videoFormats = (data.formats || []).filter(f => f.type === 'video');
    const audioFormats = (data.formats || []).filter(f => f.type === 'audio');

    if (videoFormats.length > 0) {
      const maxHeight = Math.max(...videoFormats.map(f => f.height || 0));
      videoMaxQualityTag.textContent = maxHeight >= 2160 ? '4K Ultra HD' : maxHeight >= 1080 ? `${maxHeight}p Full HD` : `${maxHeight}p HD`;
    } else {
      videoMaxQualityTag.textContent = 'Audio Only';
    }

    // Update Counts in Filter Tabs
    countAll.textContent = data.formats ? data.formats.length : 0;
    countVideo.textContent = videoFormats.length;
    countAudio.textContent = audioFormats.length;

    // Reset Filter Tab to All
    currentFilter = 'all';
    document.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
    document.getElementById('tabAll').classList.add('active');

    renderFormatCards(data.formats || []);
    resultsSection.style.display = 'block';
    resultsSection.scrollIntoView({ behavior: 'smooth', block: 'start' });
  }

  function renderFormatCards(formats) {
    formatsGrid.innerHTML = '';

    const filtered = formats.filter(f => {
      if (currentFilter === 'video') return f.type === 'video';
      if (currentFilter === 'audio') return f.type === 'audio';
      return true;
    });

    if (filtered.length === 0) {
      formatsGrid.innerHTML = `
        <div style="grid-column: 1 / -1; text-align: center; padding: 2rem; color: var(--text-dim);">
          No formats found for the selected category.
        </div>
      `;
      return;
    }

    filtered.forEach((fmt, index) => {
      const card = createFormatCard(fmt, index);
      formatsGrid.appendChild(card);
    });
  }

  function createFormatCard(fmt, index) {
    const card = document.createElement('div');
    card.className = 'format-card';

    const isVideo = fmt.type === 'video';
    const height = fmt.height || 0;

    let qualityClass = 'badge-sd';
    let qualityLabel = `${height}p`;

    if (!isVideo) {
      qualityClass = 'badge-audio';
      qualityLabel = 'HQ Audio';
    } else if (height >= 2160) {
      qualityClass = 'badge-4k';
      qualityLabel = '4K UHD';
    } else if (height >= 1440) {
      qualityClass = 'badge-2k';
      qualityLabel = '1440p 2K';
    } else if (height >= 1080) {
      qualityClass = 'badge-1080p';
      qualityLabel = '1080p FHD';
    } else if (height >= 720) {
      qualityClass = 'badge-720p';
      qualityLabel = '720p HD';
    }

    const typeDesc = isVideo
      ? 'Merged Video + Clean Audio (FFmpeg)'
      : `High Quality MP3 Audio Stream (${Math.round(fmt.abr || 128)} kbps)`;

    card.innerHTML = `
      <div class="format-top-row">
        <div class="format-badge-group">
          <span class="quality-badge ${qualityClass}">${qualityLabel}</span>
          <span class="ext-badge">${fmt.ext || (isVideo ? 'mp4' : 'mp3')}</span>
        </div>
      </div>
      <h4 class="format-label">${fmt.label || 'Format'}</h4>
      <p class="format-description">
        <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
          ${isVideo ? '<polygon points="5 3 19 12 5 21 5 3"></polygon>' : '<path d="M9 18V5l12-2v13"></path><circle cx="6" cy="18" r="3"></circle><circle cx="18" cy="16" r="3"></circle>'}
        </svg>
        <span>${typeDesc}</span>
      </p>
      <div class="format-actions">
        <button class="btn-download-format btn-dl" data-url="${fmt.download_url}" data-label="${fmt.label}">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <path d="M21 15v4a2 2 0 0 1-2 2H5a2 2 0 0 1-2-2v-4"></path>
            <polyline points="7 10 12 15 17 10"></polyline>
            <line x1="12" y1="15" x2="12" y2="3"></line>
          </svg>
          <span>Download</span>
        </button>
        <button class="btn-format-secondary btn-copy-link" data-url="${fmt.download_url}" title="Copy Download Link">
          <svg viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2">
            <rect x="9" y="9" width="13" height="13" rx="2" ry="2"></rect>
            <path d="M5 15H4a2 2 0 0 1-2-2V4a2 2 0 0 1 2-2h9a2 2 0 0 1 2 2v1"></path>
          </svg>
        </button>
        <button class="btn-format-secondary btn-preview-stream" data-type="${fmt.type}" data-url="${fmt.download_url}" data-label="${fmt.label}" title="Stream Preview">
          <svg viewBox="0 0 24 24" fill="currentColor">
            <polygon points="5 3 19 12 5 21 5 3"></polygon>
          </svg>
        </button>
      </div>
    `;

    // Download button handler
    const dlBtn = card.querySelector('.btn-dl');
    dlBtn.addEventListener('click', () => {
      triggerDownload(fmt.download_url, fmt.label, dlBtn);
    });

    // Copy link button handler
    const copyBtn = card.querySelector('.btn-copy-link');
    copyBtn.addEventListener('click', () => {
      copyToClipboard(fmt.download_url, 'Download link copied to clipboard!');
    });

    // Preview stream handler
    const previewBtn = card.querySelector('.btn-preview-stream');
    previewBtn.addEventListener('click', () => {
      openMediaPreview(fmt);
    });

    return card;
  }

  // --------------------------------------------------------------------------
  // Download Trigger & Progress Banner
  // --------------------------------------------------------------------------
  async function triggerDownload(downloadUrl, label, btn) {
    const origHtml = btn ? btn.innerHTML : '';
    if (btn) {
      btn.disabled = true;
      btn.innerHTML = `
        <span class="spinner" style="width: 14px; height: 14px; border-width: 2px;"></span>
        <span>Preparing...</span>
      `;
    }

    showDownloadBanner(
      `Preparing ${label}...`,
      'yt-dlp is downloading streams & FFmpeg is merging audio/video. Please wait a few moments...'
    );

    // Prepare media on server first so the user gets instant, reliable file saving
    const prepareUrl = downloadUrl.replace('/api/download', '/api/prepare');

    try {
      const response = await fetch(prepareUrl, {
        headers: { 'Accept': 'application/json' }
      });

      const data = await response.json();

      if (!response.ok || !data.success) {
        throw new Error(data.error || 'Failed to prepare download.');
      }

      showDownloadBanner(
        `✓ Download Ready!`,
        `Saved as ${data.file_name || label}. Starting download now...`
      );

      // Trigger instantaneous download now that the file is ready on the server
      window.location.href = data.download_url;

      if (btn) {
        btn.innerHTML = `<span>✓ Started!</span>`;
        setTimeout(() => {
          btn.innerHTML = origHtml;
          btn.disabled = false;
        }, 4000);
      }

      showToast(`Download started for ${label}`, 'success');
    } catch (err) {
      console.error('Download prepare error:', err);
      showToast(`Download failed: ${err.message}`, 'error');
      showDownloadBanner(
        `Download Failed`,
        err.message || 'Error occurred while processing media file.'
      );
      if (btn) {
        btn.innerHTML = origHtml;
        btn.disabled = false;
      }
    }
  }

  function showDownloadBanner(title, subtitle) {
    bannerTitle.textContent = title;
    bannerSubtitle.textContent = subtitle;
    downloadStatusBanner.style.display = 'block';

    // Auto-hide after 12 seconds
    clearTimeout(window._bannerTimer);
    window._bannerTimer = setTimeout(() => {
      downloadStatusBanner.style.display = 'none';
    }, 12000);
  }

  // --------------------------------------------------------------------------
  // Media Preview Modal
  // --------------------------------------------------------------------------
  function openMediaPreview(format) {
    previewModalTitle.textContent = `${currentVideoData ? currentVideoData.title : 'Preview'} - ${format.label}`;
    btnModalDirectDownload.href = format.download_url;

    // Use stream=1 for inline streaming playback in player
    const streamUrl = format.download_url + (format.download_url.includes('?') ? '&stream=1' : '?stream=1');

    mediaContainer.innerHTML = '';
    if (format.type === 'video') {
      const video = document.createElement('video');
      video.src = streamUrl;
      video.controls = true;
      video.autoplay = true;
      video.playsInline = true;
      mediaContainer.appendChild(video);
    } else {
      const audio = document.createElement('audio');
      audio.src = streamUrl;
      audio.controls = true;
      audio.autoplay = true;
      mediaContainer.appendChild(audio);
    }

    previewModal.style.display = 'flex';
  }

  function closeMediaPreview() {
    previewModal.style.display = 'none';
    mediaContainer.innerHTML = '';
  }

  // --------------------------------------------------------------------------
  // History Management (localStorage)
  // --------------------------------------------------------------------------
  function saveToHistory(item) {
    try {
      let history = getHistory();
      // Remove duplicate if exists
      history = history.filter(h => h.sourceUrl !== item.sourceUrl);
      history.unshift({
        title: item.title,
        thumbnail: item.thumbnail,
        duration: item.duration,
        sourceUrl: item.sourceUrl,
        date: new Date().toLocaleTimeString([], { hour: '2-digit', minute: '2-digit' })
      });
      // Keep only top 8
      if (history.length > 8) history = history.slice(0, 8);
      localStorage.setItem(STORAGE_KEY, JSON.stringify(history));
      renderHistory();
    } catch (e) {
      console.warn('Could not save to history:', e);
    }
  }

  function getHistory() {
    try {
      const data = localStorage.getItem(STORAGE_KEY);
      return data ? JSON.parse(data) : [];
    } catch {
      return [];
    }
  }

  function renderHistory() {
    const history = getHistory();
    if (history.length === 0) {
      historyEmpty.style.display = 'block';
      historyList.innerHTML = '';
      historyList.appendChild(historyEmpty);
      btnClearHistory.style.display = 'none';
      return;
    }

    btnClearHistory.style.display = 'block';
    historyList.innerHTML = '';

    history.forEach(item => {
      const row = document.createElement('div');
      row.className = 'history-item';
      row.innerHTML = `
        <div class="history-item-left">
          <img src="${item.thumbnail || ''}" alt="" class="history-thumb">
          <div class="history-meta">
            <div class="history-item-title" title="${item.title}">${item.title}</div>
            <div class="history-item-date">${formatDuration(item.duration)} &bull; ${item.date || 'Recent'}</div>
          </div>
        </div>
        <div class="history-item-actions">
          <button class="btn-history-load" data-url="${item.sourceUrl}">Fetch</button>
          <button class="btn-history-delete" data-url="${item.sourceUrl}" title="Remove item">✕</button>
        </div>
      `;

      row.querySelector('.btn-history-load').addEventListener('click', () => {
        videoUrlInput.value = item.sourceUrl;
        btnClearInput.style.display = 'inline-flex';
        fetchVideoFormats(item.sourceUrl);
      });

      row.querySelector('.btn-history-delete').addEventListener('click', () => {
        removeFromHistory(item.sourceUrl);
      });

      historyList.appendChild(row);
    });
  }

  function removeFromHistory(url) {
    let history = getHistory();
    history = history.filter(h => h.sourceUrl !== url);
    localStorage.setItem(STORAGE_KEY, JSON.stringify(history));
    renderHistory();
  }

  function clearHistory() {
    localStorage.removeItem(STORAGE_KEY);
    renderHistory();
    showToast('Search history cleared.', 'info');
  }

  // --------------------------------------------------------------------------
  // Event Listeners
  // --------------------------------------------------------------------------
  function attachEventListeners() {
    // Form submit
    searchForm.addEventListener('submit', (e) => {
      e.preventDefault();
      fetchVideoFormats(videoUrlInput.value);
    });

    // Input changes
    videoUrlInput.addEventListener('input', () => {
      btnClearInput.style.display = videoUrlInput.value.length > 0 ? 'inline-flex' : 'none';
    });

    // Clear input button
    btnClearInput.addEventListener('click', () => {
      videoUrlInput.value = '';
      btnClearInput.style.display = 'none';
      videoUrlInput.focus();
    });

    // Paste from clipboard button
    btnPasteClipboard.addEventListener('click', async () => {
      try {
        const text = await navigator.clipboard.readText();
        if (text) {
          videoUrlInput.value = text;
          btnClearInput.style.display = 'inline-flex';
          showToast('URL pasted from clipboard!', 'info');
          fetchVideoFormats(text);
        } else {
          showToast('Clipboard is empty.', 'info');
        }
      } catch (err) {
        showToast('Clipboard permission denied or unavailable. Please paste manually.', 'error');
        videoUrlInput.focus();
      }
    });

    // Sample chips
    sampleChips.forEach(chip => {
      chip.addEventListener('click', () => {
        const url = chip.getAttribute('data-url');
        if (url) {
          videoUrlInput.value = url;
          btnClearInput.style.display = 'inline-flex';
          fetchVideoFormats(url);
        }
      });
    });

    // Filter Tabs
    tabsNav.addEventListener('click', (e) => {
      const targetTab = e.target.closest('.tab-btn');
      if (!targetTab) return;

      tabsNav.querySelectorAll('.tab-btn').forEach(btn => btn.classList.remove('active'));
      targetTab.classList.add('active');

      currentFilter = targetTab.getAttribute('data-filter') || 'all';
      if (currentVideoData && currentVideoData.formats) {
        renderFormatCards(currentVideoData.formats);
      }
    });

    // Refresh server status button
    btnRefreshStatus.addEventListener('click', (e) => {
      e.stopPropagation();
      checkServerStatus();
      showToast('Refreshing server health status...', 'info');
    });

    serverStatusPill.addEventListener('click', () => {
      checkServerStatus();
    });

    // Copy title & URL buttons
    btnCopyTitle.addEventListener('click', () => {
      if (currentVideoData && currentVideoData.title) {
        copyToClipboard(currentVideoData.title, 'Video title copied!');
      }
    });

    btnCopyUrl.addEventListener('click', () => {
      if (currentVideoData && currentVideoData.sourceUrl) {
        copyToClipboard(currentVideoData.sourceUrl, 'Video link copied!');
      }
    });

    // Thumbnail play overlay preview
    btnPreviewModalThumb.addEventListener('click', () => {
      if (currentVideoData && currentVideoData.formats && currentVideoData.formats.length > 0) {
        openMediaPreview(currentVideoData.formats[0]);
      }
    });

    // Modal controls
    btnClosePreviewModal.addEventListener('click', closeMediaPreview);
    btnCloseModalBtn.addEventListener('click', closeMediaPreview);
    previewModal.addEventListener('click', (e) => {
      if (e.target === previewModal) closeMediaPreview();
    });

    // Dismiss error button
    btnDismissError.addEventListener('click', hideError);

    // Banner close button
    btnCloseBanner.addEventListener('click', () => {
      downloadStatusBanner.style.display = 'none';
    });

    // Clear history button
    btnClearHistory.addEventListener('click', clearHistory);

    // API Docs Toggle
    apiDocsToggle.addEventListener('click', () => {
      const isHidden = apiDocsBody.style.display === 'none';
      apiDocsBody.style.display = isHidden ? 'flex' : 'none';
      const pill = apiDocsToggle.querySelector('.api-expand-pill');
      if (pill) pill.textContent = isHidden ? 'Collapse ▲' : 'Explore Endpoints ▼';
    });
  }

  // --------------------------------------------------------------------------
  // Helpers
  // --------------------------------------------------------------------------
  function showError(title, msg) {
    errorTitle.textContent = title;
    errorMessage.textContent = msg;
    errorAlertCard.style.display = 'flex';
  }

  function hideError() {
    errorAlertCard.style.display = 'none';
  }

  function showToast(message, type = 'info') {
    const toast = document.createElement('div');
    toast.className = `toast toast-${type}`;

    let iconSvg = '';
    if (type === 'success') {
      iconSvg = '<svg class="toast-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><path d="M22 11.08V12a10 10 0 1 1-5.93-9.14"></path><polyline points="22 4 12 14.01 9 11.01"></polyline></svg>';
    } else if (type === 'error') {
      iconSvg = '<svg class="toast-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"></circle><line x1="12" y1="8" x2="12" y2="12"></line><line x1="12" y1="16" x2="12.01" y2="16"></line></svg>';
    } else {
      iconSvg = '<svg class="toast-icon" viewBox="0 0 24 24" fill="none" stroke="currentColor" stroke-width="2"><circle cx="12" cy="12" r="10"></circle><line x1="12" y1="16" x2="12" y2="12"></line><line x1="12" y1="8" x2="12.01" y2="8"></line></svg>';
    }

    toast.innerHTML = `
      ${iconSvg}
      <span>${message}</span>
    `;

    toastContainer.appendChild(toast);

    setTimeout(() => {
      toast.style.opacity = '0';
      toast.style.transform = 'translateY(-10px)';
      setTimeout(() => toast.remove(), 250);
    }, 3500);
  }

  function copyToClipboard(text, successMsg) {
    if (!text) return;
    navigator.clipboard.writeText(text).then(() => {
      showToast(successMsg || 'Copied to clipboard!', 'success');
    }).catch(() => {
      showToast('Could not copy to clipboard.', 'error');
    });
  }

  function formatDuration(seconds) {
    if (!seconds || isNaN(seconds)) return '00:00';
    const s = Math.floor(seconds);
    const hrs = Math.floor(s / 3600);
    const mins = Math.floor((s % 3600) / 60);
    const secs = s % 60;

    if (hrs > 0) {
      return `${hrs}:${mins.toString().padStart(2, '0')}:${secs.toString().padStart(2, '0')}`;
    }
    return `${mins}:${secs.toString().padStart(2, '0')}`;
  }

  function formatDurationDetailed(seconds) {
    if (!seconds || isNaN(seconds)) return '0 seconds';
    const s = Math.floor(seconds);
    const hrs = Math.floor(s / 3600);
    const mins = Math.floor((s % 3600) / 60);
    const secs = s % 60;

    const parts = [];
    if (hrs > 0) parts.push(`${hrs} hr${hrs > 1 ? 's' : ''}`);
    if (mins > 0) parts.push(`${mins} min${mins > 1 ? 's' : ''}`);
    if (secs > 0 || parts.length === 0) parts.push(`${secs} sec${secs > 1 ? 's' : ''}`);
    return parts.join(' ');
  }

  // Anti-Bot Cookies Modal Logic
  const btnOpenCookieModal = document.getElementById('btnOpenCookieModal');

  const cookieModal = document.getElementById('cookieModal');
  const btnCloseCookieModal = document.getElementById('btnCloseCookieModal');
  const btnCloseCookieBtn = document.getElementById('btnCloseCookieBtn');
  const btnSaveCookies = document.getElementById('btnSaveCookies');
  const cookieFileInput = document.getElementById('cookieFileInput');
  const cookieTextInput = document.getElementById('cookieTextInput');
  const cookieStatusAlert = document.getElementById('cookieStatusAlert');
  const cookieBtnText = document.getElementById('cookieBtnText');

  async function checkCookieStatus() {
    try {
      const res = await fetch('api/cookies');
      const data = await res.json();
      if (data.has_cookies) {
        if (cookieBtnText) cookieBtnText.textContent = '🍪 Cookies Active';
        if (btnOpenCookieModal) {
          btnOpenCookieModal.style.background = 'rgba(34, 197, 94, 0.15)';
          btnOpenCookieModal.style.borderColor = 'rgba(34, 197, 94, 0.4)';
          btnOpenCookieModal.style.color = '#4ade80';
        }
        if (cookieStatusAlert) {
          cookieStatusAlert.style.background = 'rgba(34, 197, 94, 0.15)';
          cookieStatusAlert.style.borderColor = 'rgba(34, 197, 94, 0.4)';
          cookieStatusAlert.style.color = '#4ade80';
          cookieStatusAlert.innerHTML = `✅ <strong>Cookies Loaded:</strong> Active (${Math.round(data.size / 1024)} KB). YouTube bot challenges are bypassed!`;
        }
      } else {
        if (cookieBtnText) cookieBtnText.textContent = '🍪 Anti-Bot Cookies';
        if (btnOpenCookieModal) {
          btnOpenCookieModal.style.background = 'rgba(239, 68, 68, 0.15)';
          btnOpenCookieModal.style.borderColor = 'rgba(239, 68, 68, 0.4)';
          btnOpenCookieModal.style.color = '#f87171';
        }
        if (cookieStatusAlert) {
          cookieStatusAlert.style.background = 'rgba(245, 158, 11, 0.15)';
          cookieStatusAlert.style.borderColor = 'rgba(245, 158, 11, 0.4)';
          cookieStatusAlert.style.color = '#fbbf24';
          cookieStatusAlert.innerHTML = `⚠️ <strong>No cookies active:</strong> Datacenter IP might get challenged with "Sign in to confirm you're not a bot".`;
        }
      }
    } catch (_) {}
  }

  checkCookieStatus();

  if (btnOpenCookieModal) {
    btnOpenCookieModal.addEventListener('click', () => {
      cookieModal.style.display = 'flex';
      checkCookieStatus();
    });
  }

  function closeCookieModal() {
    if (cookieModal) cookieModal.style.display = 'none';
  }

  if (btnCloseCookieModal) btnCloseCookieModal.addEventListener('click', closeCookieModal);
  if (btnCloseCookieBtn) btnCloseCookieBtn.addEventListener('click', closeCookieModal);

  if (cookieFileInput) {
    cookieFileInput.addEventListener('change', (e) => {
      const file = e.target.files[0];
      if (file) {
        const reader = new FileReader();
        reader.onload = (event) => {
          cookieTextInput.value = event.target.result;
        };
        reader.readAsText(file);
      }
    });
  }

  if (btnSaveCookies) {
    btnSaveCookies.addEventListener('click', async () => {
      const content = cookieTextInput.value.trim();
      if (!content) {
        alert('Please paste cookies content or select a cookies.txt file.');
        return;
      }
      btnSaveCookies.disabled = true;
      btnSaveCookies.textContent = 'Saving...';
      try {
        const res = await fetch('api/cookies', {
          method: 'POST',
          headers: { 'Content-Type': 'application/json' },
          body: JSON.stringify({ cookies: content }),
        });
        const data = await res.json();
        if (data.success) {
          showToast('Cookies saved successfully! YouTube bot check bypassed.', 'success');
          checkCookieStatus();
          closeCookieModal();
        } else {
          showToast(data.error || 'Failed to save cookies.', 'error');
        }
      } catch (err) {
        showToast('Error saving cookies: ' + err, 'error');
      } finally {
        btnSaveCookies.disabled = false;
        btnSaveCookies.textContent = 'Save & Apply Cookies';
      }
    });
  }
});

