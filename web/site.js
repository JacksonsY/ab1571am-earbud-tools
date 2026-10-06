const sections = [...document.querySelectorAll('article > header[id], article > section[id]')];
const contentsLinks = [...document.querySelectorAll('.toc a')];
const progress = document.getElementById('reading-progress');
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
window.addEventListener('scroll', scheduleReadingUpdate, { passive: true });
window.addEventListener('resize', scheduleReadingUpdate);
mobileContents.querySelectorAll('a').forEach(link => {
  link.addEventListener('click', () => { mobileContents.open = false; });
});
updateReadingPosition();
