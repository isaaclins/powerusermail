// PowerUserMail Website - Interactions & Animations

document.addEventListener('DOMContentLoaded', () => {
    // Scroll animations
    initScrollAnimations();
    
    // Smooth scroll for anchor links
    initSmoothScroll();
    
    // Nav background on scroll
    initNavScroll();
    
    // Keyboard easter egg
    initKeyboardEasterEgg();
});

// Scroll-triggered animations
function initScrollAnimations() {
    const observerOptions = {
        root: null,
        rootMargin: '0px',
        threshold: 0.1
    };
    
    const observer = new IntersectionObserver((entries) => {
        entries.forEach((entry, index) => {
            if (entry.isIntersecting) {
                // Stagger the animation based on element index
                setTimeout(() => {
                    entry.target.classList.add('visible');
                }, index * 100);
                observer.unobserve(entry.target);
            }
        });
    }, observerOptions);
    
    // Observe feature cards
    document.querySelectorAll('.feature-card').forEach((card, i) => {
        card.style.transitionDelay = `${i * 0.1}s`;
        observer.observe(card);
    });
    
    // Observe shortcut groups
    document.querySelectorAll('.shortcut-group').forEach((group, i) => {
        group.style.transitionDelay = `${i * 0.15}s`;
        observer.observe(group);
    });
}

// Smooth scroll for anchor links
function initSmoothScroll() {
    document.querySelectorAll('a[href^="#"]').forEach(anchor => {
        anchor.addEventListener('click', function(e) {
            e.preventDefault();
            const target = document.querySelector(this.getAttribute('href'));
            if (target) {
                const navHeight = document.querySelector('.nav').offsetHeight;
                const targetPosition = target.getBoundingClientRect().top + window.pageYOffset - navHeight - 20;
                
                window.scrollTo({
                    top: targetPosition,
                    behavior: 'smooth'
                });
            }
        });
    });
}

// Nav background on scroll
function initNavScroll() {
    const nav = document.querySelector('.nav');
    let lastScroll = 0;
    
    window.addEventListener('scroll', () => {
        const currentScroll = window.pageYOffset;
        
        if (currentScroll > 100) {
            nav.style.background = 'rgba(10, 10, 11, 0.95)';
        } else {
            nav.style.background = 'rgba(10, 10, 11, 0.8)';
        }
        
        lastScroll = currentScroll;
    });
}

// Fun keyboard easter egg - pressing ⌘K shows a little toast
function initKeyboardEasterEgg() {
    let keys = [];
    const konami = ['k'];
    let cmdPressed = false;
    
    document.addEventListener('keydown', (e) => {
        if (e.metaKey || e.ctrlKey) {
            cmdPressed = true;
        }
        
        if (cmdPressed && e.key.toLowerCase() === 'k') {
            e.preventDefault();
            showToast('⌘K — You\'re already a power user! 🚀');
        }
    });
    
    document.addEventListener('keyup', (e) => {
        if (!e.metaKey && !e.ctrlKey) {
            cmdPressed = false;
        }
    });
}

function showToast(message) {
    // Remove existing toast
    const existingToast = document.querySelector('.toast');
    if (existingToast) {
        existingToast.remove();
    }
    
    // Create toast
    const toast = document.createElement('div');
    toast.className = 'toast';
    toast.textContent = message;
    toast.style.cssText = `
        position: fixed;
        bottom: 40px;
        left: 50%;
        transform: translateX(-50%) translateY(20px);
        background: linear-gradient(135deg, #a855f7, #ec4899);
        color: white;
        padding: 16px 32px;
        border-radius: 12px;
        font-weight: 600;
        font-size: 0.95rem;
        box-shadow: 0 10px 40px rgba(168, 85, 247, 0.4);
        opacity: 0;
        transition: all 0.3s ease;
        z-index: 1000;
    `;
    
    document.body.appendChild(toast);
    
    // Animate in
    requestAnimationFrame(() => {
        toast.style.opacity = '1';
        toast.style.transform = 'translateX(-50%) translateY(0)';
    });
    
    // Animate out
    setTimeout(() => {
        toast.style.opacity = '0';
        toast.style.transform = 'translateX(-50%) translateY(20px)';
        setTimeout(() => toast.remove(), 300);
    }, 3000);
}

// Parallax effect for background glows
document.addEventListener('mousemove', (e) => {
    const glows = document.querySelectorAll('.bg-glow');
    const x = e.clientX / window.innerWidth;
    const y = e.clientY / window.innerHeight;
    
    glows.forEach((glow, i) => {
        const speed = (i + 1) * 20;
        const offsetX = (x - 0.5) * speed;
        const offsetY = (y - 0.5) * speed;
        glow.style.transform = `translate(${offsetX}px, ${offsetY}px)`;
    });
});

// Add typing effect to hero title (optional enhancement)
function typeWriter(element, text, speed = 50) {
    let i = 0;
    element.textContent = '';
    
    function type() {
        if (i < text.length) {
            element.textContent += text.charAt(i);
            i++;
            setTimeout(type, speed);
        }
    }
    
    type();
}

