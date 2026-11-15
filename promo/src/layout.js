// 和 VeilBarPanel.show 一样摆放托盘：右边缘 = Veil 图标右边缘 + 6pt，顶边 = 菜单栏下方 6pt。
function veilU() {
  return parseFloat(getComputedStyle(document.documentElement).getPropertyValue("--u")) || 1.9;
}
function placeTray(tray, anchor, bar, root) {
  const u = veilU();
  const r = (root || document.querySelector(".poster")).getBoundingClientRect();
  const a = anchor.getBoundingClientRect();
  const b = bar.getBoundingClientRect();
  const w = tray.getBoundingClientRect().width;
  tray.style.left = a.right - r.left + 6 * u - w + "px";
  tray.style.top = b.bottom - r.top + 6 * u + "px";
}
// 把元素放在托盘里某个图标的正下方（左边缘对齐），用于镜像菜单
function placeBelow(el, target, gap, root) {
  const r = (root || document.querySelector(".poster")).getBoundingClientRect();
  const t = target.getBoundingClientRect();
  el.style.left = t.left - r.left + "px";
  el.style.top = t.bottom - r.top + gap + "px";
}
