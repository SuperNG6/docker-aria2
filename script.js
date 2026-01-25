/**
 * Docker Aria2 Best Practice
 * Advanced Interactivity Script
 */

// Wait for DOM to load
document.addEventListener('DOMContentLoaded', () => {
    initCursor();
    initVanillaTilt();
    initScrollReveal();
    initCounters();
    initNavbar();
    initTypewriter();
    initBackToTop();
});

/* =========================================
   Custom Cursor Logic
   ========================================= */
function initCursor() {
    // Only init if not touch device
    if (window.matchMedia("(pointer: coarse)").matches) return;

    const dot = document.createElement('div');
    const outline = document.createElement('div');

    dot.className = 'cursor-dot';
    outline.className = 'cursor-outline';

    document.body.appendChild(dot);
    document.body.appendChild(outline);

    window.addEventListener('mousemove', (e) => {
        const posX = e.clientX;
        const posY = e.clientY;

        // Dot follows immediately
        dot.style.left = `${posX}px`;
        dot.style.top = `${posY}px`;

        // Outline follows with slight delay (animation provided by CSS transition)
        // We use requestAnimationFrame for smoother performance if needed,
        // but CSS transition is usually performant enough for simple following.
        outline.style.left = `${posX}px`;
        outline.style.top = `${posY}px`;
    });

    // Hover effect for interactive elements
    const interactiveElements = document.querySelectorAll('a, button, .glass-card, input, select, textarea');

    interactiveElements.forEach(el => {
        el.addEventListener('mouseenter', () => {
            document.body.classList.add('hovering');
        });
        el.addEventListener('mouseleave', () => {
            document.body.classList.remove('hovering');
        });
    });
}

/* =========================================
   Navbar Logic
   ========================================= */
function initNavbar() {
    const nav = document.getElementById('navbar');
    window.addEventListener('scroll', () => {
        if (window.scrollY > 50) {
            nav.classList.add('shadow-lg');
            nav.style.background = 'rgba(2, 6, 23, 0.85)';
        } else {
            nav.classList.remove('shadow-lg');
            nav.style.background = 'rgba(15, 23, 42, 0.5)';
        }
    });
}

/* =========================================
   Scroll Reveal Logic
   ========================================= */
function initScrollReveal() {
    const observerOptions = {
        root: null,
        rootMargin: '0px',
        threshold: 0.1
    };

    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                entry.target.classList.add('active');
                // Optional: Unobserve after revealing if you want it to happen only once
                // observer.unobserve(entry.target);
            }
        });
    }, observerOptions);

    document.querySelectorAll('.reveal').forEach(el => {
        observer.observe(el);
    });
}

/* =========================================
   Typewriter Effect for Terminal
   ========================================= */
function initTypewriter() {
    const codeBlocks = document.querySelectorAll('.terminal-content pre code');

    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                const codeElement = entry.target;
                if (!codeElement.dataset.typed) {
                    codeElement.dataset.typed = "true";
                    typeText(codeElement);
                }
                observer.unobserve(codeElement);
            }
        });
    }, { threshold: 0.2 });

    codeBlocks.forEach(block => {
        block.dataset.rawCode = block.innerText; // Store raw code for clipboard
        block.style.opacity = '0'; // Hide initially
        observer.observe(block);
    });
}

function typeText(element) {
    element.style.opacity = '1';

    // Get the HTML content
    const html = element.innerHTML;
    // Split by newlines, but be careful not to break HTML tags.
    // Since the HTML is simple (just some spans), let's try a visual trick.
    // We will clear the content and append characters one by one?
    // No, that breaks tags.

    // Let's go with the "Line Reveal" approach which is safer.
    // We split by newline characters in the textContent? No.

    // Simplest robust solution:
    // Just restore the opacity. The code is already syntax highlighted.
    // Let's add a "blinking cursor" at the end to signify active terminal.

    const originalHTML = element.innerHTML;
    element.innerHTML = '';

    // Create a temporary container to parse HTML
    const tempDiv = document.createElement('div');
    tempDiv.innerHTML = originalHTML;

    // We will append nodes from tempDiv to element with delays
    const nodes = Array.from(tempDiv.childNodes);

    let delay = 0;
    nodes.forEach((node, index) => {
        // If it's a text node, we could animate chars.
        // If it's an element (span), we animate the whole span?

        // This is getting complicated to get right without visual glitches.
        // Let's stick to the Fade In Up for the whole block for now,
        // but maybe with a "typing" sound or just a cursor.

        setTimeout(() => {
            element.appendChild(node);
        }, delay);

        // Rough estimate of "typing time"
        if (node.nodeType === Node.TEXT_NODE) {
            delay += node.textContent.length * 5;
        } else {
            delay += 20;
        }
    });
}

/* =========================================
   Number Counter Animation
   ========================================= */
function initCounters() {
    const counters = document.querySelectorAll('.counter');
    const speed = 200; // The lower the slower

    const observer = new IntersectionObserver((entries) => {
        entries.forEach(entry => {
            if (entry.isIntersecting) {
                const counter = entry.target;
                const target = +counter.getAttribute('data-target');

                const updateCount = () => {
                    const count = +counter.innerText;
                    // Lower increment for higher numbers to make it smooth but not too slow
                    // Adaptive increment based on target size
                    const inc = target / speed;

                    if (count < target) {
                        // Format large numbers (e.g. 10M+)
                        const currentVal = Math.ceil(count + inc);
                        counter.innerText = currentVal;
                        setTimeout(updateCount, 20);
                    } else {
                        // Final formatting
                        if (target >= 1000000) {
                             counter.innerText = (target / 1000000).toFixed(1) + 'M';
                        } else if (target >= 1000) {
                             counter.innerText = (target / 1000).toFixed(1) + 'k';
                        } else {
                             counter.innerText = target;
                        }
                    }
                };

                updateCount();
                observer.unobserve(counter);
            }
        });
    }, { threshold: 0.5 });

    counters.forEach(counter => {
        observer.observe(counter);
    });
}

/* =========================================
   Tab Switching Logic
   ========================================= */
window.switchTab = function(tabId) {
    // Hide all contents
    document.querySelectorAll('.tab-content').forEach(el => el.classList.add('hidden'));
    document.querySelectorAll('.tab-content').forEach(el => el.classList.remove('block'));

    // Show selected
    document.getElementById(tabId).classList.remove('hidden');
    document.getElementById(tabId).classList.add('block');

    // Update buttons
    const buttons = document.querySelectorAll('.tab-btn');
    buttons.forEach(btn => {
        btn.classList.remove('bg-brand-600', 'text-white', 'shadow');
        btn.classList.add('text-gray-400', 'hover:text-white');
    });

    // Find the clicked button
    // This is a bit hacky relying on onclick attribute string, but works for simple case
    const activeBtn = Array.from(buttons).find(btn => btn.getAttribute('onclick').includes(tabId));
    if(activeBtn) {
        activeBtn.classList.remove('text-gray-400', 'hover:text-white');
        activeBtn.classList.add('bg-brand-600', 'text-white', 'shadow');
    }
}

/* =========================================
   Back to Top Logic
   ========================================= */
function initBackToTop() {
    const btn = document.getElementById('back-to-top');

    window.addEventListener('scroll', () => {
        if (window.scrollY > 300) {
            btn.classList.remove('opacity-0', 'invisible');
            btn.classList.add('opacity-100', 'visible');
        } else {
            btn.classList.add('opacity-0', 'invisible');
            btn.classList.remove('opacity-100', 'visible');
        }
    });

    btn.addEventListener('click', () => {
        window.scrollTo({
            top: 0,
            behavior: 'smooth'
        });
    });
}

/* =========================================
   Copy to Clipboard
   ========================================= */
window.copyCode = function(btn) {
    // Navigate to the pre element inside the code-block wrapper
    // Structure: .terminal-header > .terminal-controls + .copy-btn ... wait, HTML structure changed
    // Let's assume standard structure relative to button

    // We need to look at the new HTML structure for terminal windows
    // It will be: window > header + content > pre > code
    const terminalWindow = btn.closest('.terminal-window');
    const pre = terminalWindow.querySelector('pre');
    const codeEl = terminalWindow.querySelector('code');

    if (!pre) return;

    // Prefer the stored raw code if available (from typewriter init)
    // otherwise fallback to innerText
    const code = (codeEl && codeEl.dataset.rawCode) ? codeEl.dataset.rawCode : pre.innerText;

    navigator.clipboard.writeText(code).then(() => {
        const originalIcon = btn.innerHTML;
        btn.innerHTML = '<i class="fa-solid fa-check text-green-400"></i>';
        setTimeout(() => {
            btn.innerHTML = originalIcon;
        }, 2000);
    });
}

/* =========================================
   Vanilla Tilt (3D Effect)
   ========================================= */
function initVanillaTilt() {
    class VanillaTilt {
        constructor(element, settings = {}) {
            this.element = element;
            this.settings = Object.assign({
                max: 10,
                perspective: 1000,
                scale: 1.02,
                speed: 400,
                glare: true,
                "max-glare": 0.15
            }, settings);

            this.init();
        }

        init() {
            this.element.addEventListener("mousemove", this.onMouseMove.bind(this));
            this.element.addEventListener("mouseenter", this.onMouseEnter.bind(this));
            this.element.addEventListener("mouseleave", this.onMouseLeave.bind(this));
        }

        onMouseMove(event) {
            const rect = this.element.getBoundingClientRect();
            const x = event.clientX - rect.left;
            const y = event.clientY - rect.top;

            const centerX = rect.width / 2;
            const centerY = rect.height / 2;

            const rotateX = ((y - centerY) / centerY) * -this.settings.max;
            const rotateY = ((x - centerX) / centerX) * this.settings.max;

            this.element.style.transform = `perspective(${this.settings.perspective}px) rotateX(${rotateX}deg) rotateY(${rotateY}deg) scale3d(${this.settings.scale}, ${this.settings.scale}, ${this.settings.scale})`;

            if (this.settings.glare) {
                if (!this.glareElement) {
                    this.createGlare();
                }
                const glareX = (x / rect.width) * 100;
                const glareY = (y / rect.height) * 100;
                this.glareElement.style.background = `radial-gradient(circle at ${glareX}% ${glareY}%, rgba(255, 255, 255, ${this.settings["max-glare"]}), transparent)`;
                this.glareElement.style.opacity = "1";
            }
        }

        createGlare() {
            this.glareElement = document.createElement("div");
            this.glareElement.className = "js-tilt-glare";
            this.glareElement.style.position = "absolute";
            this.glareElement.style.top = "0";
            this.glareElement.style.left = "0";
            this.glareElement.style.width = "100%";
            this.glareElement.style.height = "100%";
            this.glareElement.style.pointerEvents = "none";
            this.glareElement.style.borderRadius = getComputedStyle(this.element).borderRadius;
            this.glareElement.style.zIndex = "2"; // Above content gradient
            this.element.appendChild(this.glareElement);
        }

        onMouseEnter() {
            this.element.style.transition = `transform ${this.settings.speed}ms cubic-bezier(.03,.98,.52,.99)`;
            if (this.glareElement) this.glareElement.style.opacity = "1";
        }

        onMouseLeave() {
            this.element.style.transition = `transform ${this.settings.speed}ms cubic-bezier(.03,.98,.52,.99)`;
            this.element.style.transform = `perspective(${this.settings.perspective}px) rotateX(0deg) rotateY(0deg) scale3d(1, 1, 1)`;
            if (this.glareElement) {
                this.glareElement.style.opacity = "0";
            }
        }
    }

    // Initialize on all glass cards
    document.querySelectorAll('.glass-card').forEach(card => {
        new VanillaTilt(card);
    });
}
