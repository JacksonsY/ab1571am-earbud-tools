const sections = [...document.querySelectorAll('[data-section]')];
const contentsLinks = [...document.querySelectorAll('.contents a')];
const progress = document.getElementById('progress-line');
const mobileContents = document.querySelector('.mobile-contents');
let scheduled = false;

function updateReadingPosition() {
  scheduled = false;
  const total = document.documentElement.scrollHeight - window.innerHeight;
  progress.style.width = (total > 0 ? Math.min(100, Math.max(0, window.scrollY / total * 100)) : 100) + '%';
  let current = sections[0].id;
  sections.forEach(section => {
    if (section.getBoundingClientRect().top <= 145) current = section.id;
  });
  contentsLinks.forEach(link => {
    if (link.getAttribute('href') === '#' + current) link.setAttribute('aria-current', 'location');
    else link.removeAttribute('aria-current');
  });
}
function scheduleReadingUpdate() {
  if (!scheduled) {
    scheduled = true;
    window.requestAnimationFrame(updateReadingPosition);
  }
}
function revealEvidence(id) {
  const target = document.getElementById(id);
  if (target instanceof HTMLDetailsElement && target.classList.contains('evidence-item')) target.open = true;
}

document.addEventListener('click', event => {
  const link = event.target.closest?.('a[href^="#"]');
  if (!link) return;
  revealEvidence(link.getAttribute('href').slice(1));
  if (mobileContents.contains(link)) mobileContents.open = false;
});
window.addEventListener('hashchange', () => {
  revealEvidence(window.location.hash.slice(1));
  scheduleReadingUpdate();
});
window.addEventListener('scroll', scheduleReadingUpdate, { passive: true });
window.addEventListener('resize', scheduleReadingUpdate);
document.querySelectorAll('details').forEach(detail => detail.addEventListener('toggle', scheduleReadingUpdate));
revealEvidence(window.location.hash.slice(1));
updateReadingPosition();
