// 示意用的通用单色图标（自绘，非任何品牌标志）。在页面里写 <i class="g" data-g="cloud"></i> 即可。
(function () {
  const S = 'fill="none" stroke="currentColor" stroke-width="1.6" stroke-linecap="round" stroke-linejoin="round"';
  const G = {
    cloud: `<path ${S} d="M5.5 14h7.2a3.1 3.1 0 0 0 .4-6.2A4.3 4.3 0 0 0 4.9 8.6 2.7 2.7 0 0 0 5.5 14z"/>`,
    wave: `<path ${S} d="M3 9v0M6 6.5v5M9 4v10M12 6.5v5M15 8.5v1"/>`,
    moon: `<path ${S} d="M14.6 11.4A6 6 0 0 1 6.6 3.4a6 6 0 1 0 8 8z"/>`,
    bolt: `<path ${S} d="M10 2.5 4.5 10H9l-1 5.5L13.5 8H9z"/>`,
    timer: `<circle ${S} cx="9" cy="10" r="5.6"/><path ${S} d="M9 10V7M7.4 2.6h3.2"/>`,
    clip: `<rect ${S} x="4" y="3.6" width="10" height="12" rx="2"/><path ${S} d="M7 3.6V3h4v.6M6.8 8h4.4M6.8 11h3"/>`,
    drop: `<path ${S} d="M9 2.8s4.6 5 4.6 8.3a4.6 4.6 0 0 1-9.2 0C4.4 7.8 9 2.8 9 2.8z"/>`,
    grid: `<rect ${S} x="3.2" y="3.2" width="4.6" height="4.6" rx="1.2"/><rect ${S} x="10.2" y="3.2" width="4.6" height="4.6" rx="1.2"/><rect ${S} x="3.2" y="10.2" width="4.6" height="4.6" rx="1.2"/><rect ${S} x="10.2" y="10.2" width="4.6" height="4.6" rx="1.2"/>`,
    ring: `<circle ${S} cx="9" cy="9" r="6"/><circle fill="currentColor" cx="9" cy="9" r="2.2"/>`,
    chart: `<path ${S} d="M3 15h12M5 12.5V9M9 12.5V4.5M13 12.5V7"/>`,
    key: `<circle ${S} cx="6" cy="9" r="3"/><path ${S} d="M9 9h6.5M13 9v2.4M15.5 9v1.8"/>`,
    note: `<path ${S} d="M7 13.5V4.2l7-1.4v9.3"/><circle fill="currentColor" cx="5.4" cy="13.6" r="1.9"/><circle fill="currentColor" cx="12.4" cy="12.2" r="1.9"/>`,
    shield: `<path ${S} d="M9 2.6 3.8 4.6v4.2c0 3.3 2.2 5.6 5.2 6.6 3-1 5.2-3.3 5.2-6.6V4.6z"/>`,
    cup: `<path ${S} d="M3.8 7h8.4v4.2a3.6 3.6 0 0 1-3.6 3.6h-1.2a3.6 3.6 0 0 1-3.6-3.6zM12.2 8.2h1a1.9 1.9 0 0 1 0 3.8h-1M6.6 2.8v1.8M9.4 2.8v1.8"/>`,
    leaf: `<path ${S} d="M3.6 14.4C3.6 7.6 8 3.6 14.6 3.4c.2 6.6-3.8 11-10.4 11zM3.6 14.4 9.4 8.6"/>`,
    // 系统常见指示
    wifi: `<path ${S} d="M2.6 7.2a9.4 9.4 0 0 1 12.8 0M4.9 9.8a6 6 0 0 1 8.2 0M7.2 12.3a2.6 2.6 0 0 1 3.6 0"/><circle fill="currentColor" cx="9" cy="14.6" r="1"/>`,
    battery: `<rect fill="none" stroke="currentColor" stroke-width="1.3" x="1.6" y="5.4" width="13" height="7.2" rx="2.2" opacity=".55"/><rect fill="currentColor" x="3.1" y="6.9" width="8.4" height="4.2" rx="1"/><path fill="currentColor" d="M15.6 7.6c.8.2 1.2.7 1.2 1.4s-.4 1.2-1.2 1.4z" opacity=".55"/>`,
    toggles: `<rect ${S} x="2.6" y="3.6" width="12.8" height="4.4" rx="2.2"/><rect ${S} x="2.6" y="10" width="12.8" height="4.4" rx="2.2"/><circle fill="currentColor" cx="11.8" cy="5.8" r="1.4"/><circle fill="currentColor" cx="6.2" cy="12.2" r="1.4"/>`,
    // Veil 自己的图标（SF Symbols chevron.left / chevron.right 的近似）
    "veil-closed": `<path fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" d="M11.2 3.6 5.8 9l5.4 5.4"/>`,
    "veil-open": `<path fill="none" stroke="currentColor" stroke-width="2.2" stroke-linecap="round" stroke-linejoin="round" d="M6.8 3.6 12.2 9l-5.4 5.4"/>`,
    check: `<circle fill="currentColor" cx="9" cy="9" r="8"/><path fill="none" stroke="#fff" stroke-width="2" stroke-linecap="round" stroke-linejoin="round" d="m5.4 9.2 2.4 2.4 4.8-5"/>`,
    tray: `<path ${S} d="M2.8 10.2 4.6 4h8.8l1.8 6.2v3.6a1.2 1.2 0 0 1-1.2 1.2H4a1.2 1.2 0 0 1-1.2-1.2zM2.8 10.2h3.8l.8 1.8h3.2l.8-1.8h3.8"/>`,
    menubar: `<rect ${S} x="2.4" y="3.4" width="13.2" height="11.2" rx="2"/><path ${S} d="M2.4 6.8h13.2"/>`,
    gear: `<circle ${S} cx="9" cy="9" r="2.4"/><path ${S} d="M9 2.4v2M9 13.6v2M2.4 9h2M13.6 9h2M4.3 4.3l1.4 1.4M12.3 12.3l1.4 1.4M4.3 13.7l1.4-1.4M12.3 5.7l1.4-1.4"/>`,
    info: `<circle ${S} cx="9" cy="9" r="6.6"/><path ${S} d="M9 8.2v4.2"/><circle fill="currentColor" cx="9" cy="5.8" r="1"/>`,
    refresh: `<path ${S} d="M14.2 9a5.2 5.2 0 1 1-1.6-3.8M14.2 3.2v2.6h-2.6"/>`,
    cursor: `<path fill="#fff" stroke="#000" stroke-width="1" stroke-linejoin="round" d="M4 2.2v12.4l3-2.9 2 4.6 2-.9-2-4.5h4.2z"/>`,
  };
  document.querySelectorAll("i.g[data-g]").forEach((el) => {
    const body = G[el.dataset.g];
    if (!body) { el.style.outline = "2px solid red"; return; }
    el.innerHTML = `<svg viewBox="0 0 18 18" aria-hidden="true">${body}</svg>`;
  });
})();
