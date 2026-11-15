// STOCKPRO · Etapa 1: navegación de maqueta solamente; no hay datos reales conectados.
const menuButton = document.querySelector('.mobile-menu');
const sidebar = document.querySelector('.sidebar');
menuButton?.addEventListener('click', () => {
  const open = sidebar.classList.toggle('open');
  menuButton.setAttribute('aria-expanded', String(open));
});
document.querySelectorAll('.nav-link').forEach((link) => {
  link.addEventListener('click', (event) => {
    if (link.getAttribute('href') !== '#inicio') event.preventDefault();
    document.querySelectorAll('.nav-link').forEach((item) => item.classList.remove('active'));
    link.classList.add('active');
    sidebar.classList.remove('open');
    menuButton?.setAttribute('aria-expanded', 'false');
  });
});
