// Float Selectize menus outside clipping cards, including dynamically added inputs.
(function () {
  function bindMenus() {
    document.querySelectorAll('select').forEach(element => {
      const select = element.selectize;
      if (!select || select.rdataFloating) return;
      select.rdataFloating = true;
      select.positionDropdown = function () {
        if (!this.isOpen) return;
        const control = this.$control[0], menu = this.$dropdown[0];
        const parent = control.closest('dialog') || document.body;
        if (menu.parentElement !== parent) parent.appendChild(menu);
        const box = control.getBoundingClientRect();
        const below = Math.max(0, window.innerHeight - box.bottom - 10), above = Math.max(0, box.top - 10);
        const up = below < 200 && above > below;
        const available = Math.max(40, Math.min(420, up ? above : below));
        menu.classList.add('rdata-floating-menu');
        Object.assign(menu.style, {position: 'fixed', width: box.width + 'px', left: Math.max(4, Math.min(box.left, window.innerWidth-box.width-4)) + 'px', top: box.bottom + 'px', bottom: 'auto'});
        this.$dropdown_content.css('max-height', available + 'px');
        if (up) menu.style.top = Math.max(4, box.top - menu.getBoundingClientRect().height) + 'px';
      };
      select.on('dropdown_open', function () {
        // Run after existing per-control callbacks (including analysis selection).
        requestAnimationFrame(() => this.positionDropdown());
      });
      select.on('destroy', function () {this.$dropdown.remove();});
    });
  }
  document.addEventListener('mousedown', bindMenus, true);
  document.addEventListener('focusin', bindMenus, true);
  function reposition(event) {
    document.querySelectorAll('select').forEach(element => {
      const select=element.selectize;
      if(select?.isOpen && !select.$dropdown[0].contains(event.target)) select.positionDropdown();
    });
  }
  window.addEventListener('resize', reposition);
  document.addEventListener('scroll', reposition, true);
  document.addEventListener('DOMContentLoaded', bindMenus);
  if(window.jQuery) jQuery(document).on('shiny:bound shiny:connected', () => setTimeout(bindMenus, 0));
})();
