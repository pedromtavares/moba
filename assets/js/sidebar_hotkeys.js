export function initSidebarHotkeys() {
  document.addEventListener('keydown', event => {
    if (!/^[1-6]$/.test(event.key) || event.defaultPrevented || event.repeat || event.isComposing ||
        event.altKey || event.ctrlKey || event.metaKey || event.shiftKey) return;
    // Number keys belong to items throughout the battle screen.
    if (document.querySelector('#battle-page')) return;
    if (event.target.closest("input, textarea, select, [role='textbox'], [role='switch'], [role='slider'], [contenteditable]:not([contenteditable='false'])")) return;
    const dialogOpen = Array.from(document.querySelectorAll("dialog[open], [role='dialog'], .modal.show, .modal.d-block, .swal-overlay--show-modal, .shepherd-enabled"))
      .some(element => element.getClientRects().length);
    if (dialogOpen) return;

    const link = document.querySelector(`#game-sidebar a[data-sidebar-hotkey="${event.key}"]`);
    if (!link || !link.getClientRects().length || link.getAttribute('aria-disabled') === 'true') return;
    event.preventDefault();
    link.click();
  });
}
