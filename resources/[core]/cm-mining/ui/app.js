// cm-mining/ui/app.js
// Shift HUD event listener for Davis Quartz mining operations.

window.addEventListener('DOMContentLoaded', () => {
    const hudContainer = document.getElementById('mining-hud');
    const cartOreEl = document.getElementById('cart-ore');
    const cartIngotsEl = document.getElementById('cart-ingots');
    const totalMinedEl = document.getElementById('total-mined');
    const totalSmeltedEl = document.getElementById('total-smelted');
    const objectiveTextEl = document.getElementById('objective-text');

    window.addEventListener('message', (event) => {
        const item = event.data;
        if (!item || !item.action) return;

        if (item.action === 'cmMining:updateHud') {
            const data = item.data;
            if (!data || !data.visible || !data.onShift) {
                if (hudContainer) hudContainer.style.display = 'none';
                return;
            }

            if (hudContainer) hudContainer.style.display = 'block';

            if (cartOreEl) {
                cartOreEl.textContent = `${data.cartOre || 0} / ${data.maxCartOre || 30}`;
            }

            if (cartIngotsEl) {
                cartIngotsEl.textContent = `${data.cartIngots || 0}`;
            }

            if (totalMinedEl) {
                totalMinedEl.textContent = `${data.oreMined || 0}`;
            }

            if (totalSmeltedEl) {
                totalSmeltedEl.textContent = `${data.ingotsSmelted || 0}`;
            }

            if (objectiveTextEl && data.objective) {
                objectiveTextEl.textContent = data.objective;
            }
        }
    });
});

