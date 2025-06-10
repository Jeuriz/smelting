
let furnaceData = {
         items: {},
         fuel: {},
         smeltingRules: {},
         selectedFuel: null,
         selectedFuelAmount: 0,
         maxFuelAmount: 0,
         selectedOres: {},
         currentOutput: {},
         outputItems: {},
         playerSkills: {},
         skillLabels: {},
         slotSkills: {},
         availableSlots: 1 // Por defecto solo el primer slot
     };

     // Sistema de tooltip mejorado con skills
     function showTooltip(element, text) {
         const tooltip = document.getElementById('tooltip');
         const rect = element.getBoundingClientRect();
         tooltip.textContent = text;
         tooltip.style.left = rect.left + (rect.width / 2) + 'px';
         tooltip.style.top = (rect.top - 30) + 'px';
         tooltip.style.transform = 'translateX(-50%)';
         tooltip.classList.add('show');
     }

     function hideTooltip() {
         document.getElementById('tooltip').classList.remove('show');
     }

     // Función para verificar si un slot está disponible
     function isSlotAvailable(slotNumber) {
         const requiredSkill = furnaceData.slotSkills[slotNumber];
         
         // Si no requiere skill, está disponible
         if (!requiredSkill) {
             return true;
         }
         
         // Verificar si el jugador tiene la skill
         return furnaceData.playerSkills[requiredSkill] === true;
     }

     // Función para calcular slots disponibles
     function calculateAvailableSlots() {
         let count = 0;
         for (let i = 1; i <= 5; i++) {
             if (isSlotAvailable(i)) {
                 count++;
             }
         }
         furnaceData.availableSlots = count;
         return count;
     }

     // Función para refrescar la UI
     function refreshUI() {
         const refreshBtn = document.querySelector('.btn-refresh');
         
         refreshBtn.classList.add('refreshing');
         
         setTimeout(() => {
             refreshBtn.classList.remove('refreshing');
         }, 500);
         
         // Solo resetear selecciones, no la estructura completa
         resetSelections();
         
         fetch(`https://${GetParentResourceName()}/refreshUI`, {
             method: 'POST',
             headers: {
                 'Content-Type': 'application/json; charset=UTF-8',
             },
             body: JSON.stringify({})
         }).then(response => {
             console.log('Refresh solicitado al servidor');
         }).catch(error => {
             console.error('Error al refrescar UI:', error);
         });
     }

     // Función para resetear solo las selecciones (no la estructura)
     function resetSelections() {
         furnaceData.selectedFuel = null;
         furnaceData.selectedFuelAmount = 0;
         furnaceData.maxFuelAmount = 0;
         furnaceData.selectedOres = {};
         furnaceData.currentOutput = {};
         
         // Resetear fuel display
         const fuelSlot = document.getElementById('fuelSlot');
         const fuelDisplay = document.getElementById('fuelDisplay');
         fuelSlot.classList.remove('has-fuel');
         fuelDisplay.innerHTML = `<div class="slot-icon">🔥</div>`;
         
         // Ocultar controles de cantidad de combustible
         document.getElementById('fuelQuantityControls').style.display = 'none';
         document.getElementById('fuelSelector').classList.remove('show');
         
         // Limpiar selecciones de minerales (mantener estructura)
         const oreItems = document.querySelectorAll('.ore-item');
         oreItems.forEach(item => {
             item.classList.remove('selected');
             const input = item.querySelector('.quantity-input');
             if (input) {
                 input.value = 1;
             }
         });
         
         // Limpiar slots de input (mantener candados)
         updateInputSlots();
         
         // Limpiar preview de output (mantener items ya procesados)
         const outputSlots = document.querySelectorAll('#outputSlots .slot');
         outputSlots.forEach((slot, index) => {
             if (index >= Object.keys(furnaceData.outputItems).length) {
                 slot.innerHTML = '';
                 slot.classList.remove('has-item');
                 slot.style.opacity = '1';
             }
         });
         
         updateUI();
         hideTooltip();
         
         console.log('Selecciones reseteadas');
     }

     // Event listener para mensajes
     window.addEventListener('message', function(event) {
         const data = event.data;
         
         if (data.action === 'openSmelting') {
             furnaceData.items = data.items || {};
             furnaceData.fuel = data.fuel || {};
             furnaceData.smeltingRules = data.smeltingRules || {};
             furnaceData.outputItems = data.outputItems || {};
             furnaceData.playerSkills = data.playerSkills || {};
             furnaceData.slotSkills = data.slotSkills || {};
             furnaceData.selectedOres = {};
             furnaceData.currentOutput = {};
             
             calculateAvailableSlots();
             setupFurnaceUI();
             document.getElementById('furnaceContainer').classList.add('show');
         } else if (data.action === 'closeSmelting') {
             document.getElementById('furnaceContainer').classList.remove('show');
         } else if (data.action === 'showProgress') {
             showProgress(data.totalTime);
         } else if (data.action === 'refreshComplete') {
             // Manejar refresh de datos
             furnaceData.items = data.items || {};
             furnaceData.fuel = data.fuel || {};
             furnaceData.smeltingRules = data.smeltingRules || {};
             furnaceData.outputItems = data.outputItems || {};
             furnaceData.playerSkills = data.playerSkills || {};
             furnaceData.slotSkills = data.slotSkills || {};
             
             calculateAvailableSlots();
             // Recrear la UI con los nuevos datos
             setupFurnaceUI();
             console.log('UI refreshed with new data and skills');
         }
     });

     function setupFurnaceUI() {
         setupInputSlots(); // Configurar candados en slots
         setupOreSelection();
         updateOutputItems();
         updateUI();
     }

     // Función para configurar los slots de input con candados
     function setupInputSlots() {
         const inputSlots = document.querySelectorAll('#inputSlots .slot');
         
         inputSlots.forEach((slot, index) => {
             const slotNumber = index + 1; // Los slots van de 1 a 5
             
             // Limpiar el slot
             slot.innerHTML = '';
             slot.classList.remove('skill-locked', 'has-item');
             
             if (!isSlotAvailable(slotNumber)) {
                 // Slot bloqueado por skill
                 slot.classList.add('skill-locked');
                 const requiredSkill = furnaceData.slotSkills[slotNumber];
                 
                 slot.innerHTML = `
                     <div class="slot-lock-icon">🔒</div>
                     <div class="slot-skill-label">${requiredSkill}</div>
                 `;
                 
                 // Agregar tooltip para skills bloqueadas
                 slot.addEventListener('mouseenter', function() {
                     showTooltip(this, `Requiered aprender Habilidad: ${requiredSkill}`);
                 });
                 
                 slot.addEventListener('mouseleave', function() {
                     hideTooltip();
                 });
             }
         });
     }

     function updateOutputItems() {
         const outputSlots = document.querySelectorAll('#outputSlots .slot');
         
         // Limpiar slots primero
         outputSlots.forEach(slot => {
             slot.innerHTML = '';
             slot.classList.remove('has-item');
             slot.style.opacity = '1';
         });
         
         if (Object.keys(furnaceData.outputItems).length > 0) {
             let slotIndex = 0;
             for (const [item, amount] of Object.entries(furnaceData.outputItems)) {
                 if (slotIndex >= 10) break;
                 
                 const slot = outputSlots[slotIndex];
                 slot.classList.add('has-item');
                 slot.innerHTML = `
                     <div class="slot-item">
                         <div class="slot-icon">
                             <img src="nui://inventory_images/images/${item}.webp" alt="${item}" onerror="this.style.display='none'; this.parentElement.innerHTML='📦'">
                         </div>
                         <span class="slot-count">x${amount}</span>
                     </div>
                 `;
                 
                 slotIndex++;
             }
         }
     }

     function setupOreSelection() {
         const oreSelection = document.getElementById('oreSelection');
         oreSelection.innerHTML = '';
         
         for (const [itemName, maxAmount] of Object.entries(furnaceData.items)) {
             if (furnaceData.smeltingRules[itemName]) {
                 const oreItem = document.createElement('div');
                 oreItem.className = 'ore-item';
                 oreItem.setAttribute('data-ore', itemName);
                 oreItem.setAttribute('data-max-amount', maxAmount);
                 
                 // Verificar si el jugador puede seleccionar más ores
                 const selectedCount = Object.keys(furnaceData.selectedOres).length;
                 const canSelect = selectedCount < furnaceData.availableSlots;
                 
                 if (!canSelect && !furnaceData.selectedOres[itemName]) {
                     oreItem.classList.add('skill-locked');
                 }
                 
                 oreItem.innerHTML = `
                     <div class="ore-header">
                         <div class="ore-icon">
                             <img src="nui://inventory_images/images/${itemName}.webp" alt="${itemName}" onerror="this.style.display='none'; this.parentElement.innerHTML='⛏️'">
                         </div>
                         <div class="ore-info">
                             <div class="ore-name">${formatItemName(itemName)}</div>
                             <div class="ore-available">Available: ${maxAmount}</div>
                         </div>
                     </div>
                     <div class="ore-quantity-controls">
                         <button class="quantity-btn" onclick="adjustOreQuantity('${itemName}', -1)">-</button>
                         <input type="number" class="quantity-input" id="ore_${itemName}" min="1" max="${maxAmount}" value="1" onchange="updateOreQuantity('${itemName}')">
                         <button class="quantity-btn" onclick="adjustOreQuantity('${itemName}', 1)">+</button>
                     </div>
                 `;
                 
                 // Agregar eventos de hover para tooltip
                 oreItem.addEventListener('mouseenter', function() {
                     if (this.classList.contains('skill-locked') && !furnaceData.selectedOres[itemName]) {
                         showTooltip(this, `Need ${furnaceData.availableSlots - selectedCount} more slot(s) available`);
                     } else {
                         const rule = furnaceData.smeltingRules[itemName];
                         const tooltipText = `${formatItemName(itemName)} → ${formatItemName(rule.result)} (${rule.amount}x por unidad)`;
                         showTooltip(this, tooltipText);
                     }
                 });
                 
                 oreItem.addEventListener('mouseleave', function() {
                     hideTooltip();
                 });
                 
                 // Evento de click para seleccionar/deseleccionar
                 oreItem.addEventListener('click', function(e) {
                     if (!e.target.classList.contains('quantity-btn') && !e.target.classList.contains('quantity-input')) {
                         if (!this.classList.contains('skill-locked') || furnaceData.selectedOres[itemName]) {
                             toggleOreSelection(itemName);
                         }
                     }
                 });
                 
                 oreSelection.appendChild(oreItem);
             }
         }
     }

     function toggleOreSelection(oreName) {
         const oreItem = document.querySelector(`[data-ore="${oreName}"]`);
         
         if (furnaceData.selectedOres[oreName]) {
             // Deseleccionar
             delete furnaceData.selectedOres[oreName];
             oreItem.classList.remove('selected');
         } else {
             // Verificar límite de slots disponibles
             if (Object.keys(furnaceData.selectedOres).length >= furnaceData.availableSlots) {
                 return;
             }
             
             // Seleccionar con cantidad por defecto
             const quantityInput = document.getElementById(`ore_${oreName}`);
             const quantity = parseInt(quantityInput.value) || 1;
             furnaceData.selectedOres[oreName] = quantity;
             oreItem.classList.add('selected');
         }
         
         // Actualizar el estado de otros ores
         setupOreSelection();
         updateInputSlots();
         updateOutputPreview();
         updateUI();
     }

     function adjustOreQuantity(oreName, change) {
         const input = document.getElementById(`ore_${oreName}`);
         const maxAmount = parseInt(document.querySelector(`[data-ore="${oreName}"]`).getAttribute('data-max-amount'));
         
         let newValue = parseInt(input.value) + change;
         newValue = Math.max(1, Math.min(newValue, maxAmount));
         
         input.value = newValue;
         updateOreQuantity(oreName);
     }

     function updateOreQuantity(oreName) {
         const input = document.getElementById(`ore_${oreName}`);
         const maxAmount = parseInt(document.querySelector(`[data-ore="${oreName}"]`).getAttribute('data-max-amount'));
         
         let value = parseInt(input.value) || 1;
         value = Math.max(1, Math.min(value, maxAmount));
         
         input.value = value;
         
         // Si el ore está seleccionado, actualizar la cantidad
         if (furnaceData.selectedOres[oreName]) {
             furnaceData.selectedOres[oreName] = value;
             updateInputSlots();
             updateOutputPreview();
             updateUI();
         }
     }

     function updateInputSlots() {
         const inputSlots = document.querySelectorAll('#inputSlots .slot');
         
         // Primero restablecer todos los slots
         setupInputSlots();
         
         let slotIndex = 0;
         for (const [ore, amount] of Object.entries(furnaceData.selectedOres)) {
             // Buscar el próximo slot disponible
             while (slotIndex < 5 && !isSlotAvailable(slotIndex + 1)) {
                 slotIndex++;
             }
             
             if (slotIndex >= 5) break; // No hay más slots disponibles
             
             const slot = inputSlots[slotIndex];
             slot.classList.remove('skill-locked');
             slot.classList.add('has-item');
             slot.innerHTML = `
                 <div class="slot-item">
                     <div class="slot-icon">
                         <img src="nui://inventory_images/images/${ore}.webp" alt="${ore}" onerror="this.style.display='none'; this.parentElement.innerHTML='⛏️'">
                     </div>
                     <span class="slot-count">x${amount}</span>
                 </div>
             `;
             
             slotIndex++;
         }
     }

     function updateOutputPreview() {
         const outputSlots = document.querySelectorAll('#outputSlots .slot');
         
         // Limpiar slots que no tienen items procesados
         outputSlots.forEach((slot, index) => {
             if (index >= Object.keys(furnaceData.outputItems).length) {
                 slot.innerHTML = '';
                 slot.classList.remove('has-item');
             }
         });
         
         // Mostrar items ya procesados primero
         let slotIndex = Object.keys(furnaceData.outputItems).length;
         
         furnaceData.currentOutput = {};
         
         // Calcular output basado en los ores seleccionados con sus cantidades
         for (const [ore, amount] of Object.entries(furnaceData.selectedOres)) {
             const rule = furnaceData.smeltingRules[ore];
             if (rule) {
                 const outputAmount = rule.amount * amount;
                 if (furnaceData.currentOutput[rule.result]) {
                     furnaceData.currentOutput[rule.result] += outputAmount;
                 } else {
                     furnaceData.currentOutput[rule.result] = outputAmount;
                 }
             }
         }
         
         // Mostrar preview del output
         for (const [item, amount] of Object.entries(furnaceData.currentOutput)) {
             if (slotIndex >= 10) break;
             
             const slot = outputSlots[slotIndex];
             slot.classList.add('has-item');
             slot.style.opacity = '0.6'; // Para indicar que es un preview
             slot.innerHTML = `
                 <div class="slot-item">
                     <div class="slot-icon">
                         <img src="nui://inventory_images/images/${item}.webp" alt="${item}" onerror="this.style.display='none'; this.parentElement.innerHTML='🔧'">
                     </div>
                     <span class="slot-count">x${amount}</span>
                 </div>
             `;
             
             slotIndex++;
         }
     }

     // Función para mostrar información de skills en el botón
     function updateUI() {
         const turnOnBtn = document.getElementById('turnOnBtn');
         const hasOres = Object.keys(furnaceData.selectedOres).length > 0;
         const hasFuel = furnaceData.selectedFuel && furnaceData.selectedFuelAmount > 0;
         
         // Calcular combustible necesario total
         let totalFuelNeeded = 0;
         for (const [ore, amount] of Object.entries(furnaceData.selectedOres)) {
             const rule = furnaceData.smeltingRules[ore];
             if (rule) {
                 totalFuelNeeded += rule.fuel_needed * amount;
             }
         }
         
         const canSmelt = hasOres && hasFuel && furnaceData.selectedFuelAmount >= totalFuelNeeded;
         turnOnBtn.disabled = !canSmelt;
         
         if (!canSmelt && totalFuelNeeded > 0 && hasFuel) {
             const needed = totalFuelNeeded - furnaceData.selectedFuelAmount;
             if (needed > 0) {
                 turnOnBtn.innerHTML = `<span class="fire-icon">🔥</span> NEED ${needed} MORE FUEL`;
             } else {
                 turnOnBtn.innerHTML = `<span class="fire-icon">🔥</span> IGNITE`;
             }
         } else {
             turnOnBtn.innerHTML = `<span class="fire-icon">🔥</span> IGNITE (${furnaceData.availableSlots} slots)`;
         }
     }

     // Resto de funciones permanecen igual...
     function toggleFuelSelector() {
         const selector = document.getElementById('fuelSelector');
         selector.innerHTML = '';
         
         if (Object.keys(furnaceData.fuel).length === 0) return;
         
         for (const [fuelType, amount] of Object.entries(furnaceData.fuel)) {
             const option = document.createElement('div');
             option.className = 'fuel-option';
             option.onclick = () => selectFuel(fuelType, amount);
             
             option.innerHTML = `
                 <span>${formatItemName(fuelType)}</span>
                 <span class="fuel-amount">x${amount}</span>
             `;
             
             selector.appendChild(option);
         }
         
         selector.classList.toggle('show');
     }

     function selectFuel(fuelType, maxAmount) {
         furnaceData.selectedFuel = fuelType;
         furnaceData.maxFuelAmount = maxAmount;
         furnaceData.selectedFuelAmount = Math.min(1, maxAmount);
         
         updateFuelDisplay();
         
         // Mostrar controles de cantidad
         document.getElementById('fuelQuantityControls').style.display = 'flex';
         document.getElementById('fuelQuantityInput').value = furnaceData.selectedFuelAmount;
         document.getElementById('maxFuelAmount').textContent = maxAmount;
         
         document.getElementById('fuelSlot').classList.add('has-fuel');
         document.getElementById('fuelSelector').classList.remove('show');
         
         updateUI();
     }

     function adjustFuelQuantity(change) {
         if (!furnaceData.selectedFuel) return;
         
         const newAmount = furnaceData.selectedFuelAmount + change;
         if (newAmount >= 1 && newAmount <= furnaceData.maxFuelAmount) {
             furnaceData.selectedFuelAmount = newAmount;
             document.getElementById('fuelQuantityInput').value = newAmount;
             updateFuelDisplay();
             updateUI();
         }
     }

     function updateFuelQuantity() {
         if (!furnaceData.selectedFuel) return;
         
         const input = document.getElementById('fuelQuantityInput');
         let value = parseInt(input.value) || 1;
         
         value = Math.max(1, Math.min(value, furnaceData.maxFuelAmount));
         
         furnaceData.selectedFuelAmount = value;
         input.value = value;
         updateFuelDisplay();
         updateUI();
     }

     function updateFuelDisplay() {
         if (!furnaceData.selectedFuel) return;
         
         const fuelDisplay = document.getElementById('fuelDisplay');
         fuelDisplay.innerHTML = `
             <div class="slot-icon">
                 <img src="nui://inventory_images/images/${furnaceData.selectedFuel}.webp" alt="${furnaceData.selectedFuel}" onerror="this.style.display='none'; this.parentElement.innerHTML='🪵'">
             </div>
             <span class="slot-count">x${furnaceData.selectedFuelAmount}</span>
         `;
     }

     function startSmelting() {
         if (!furnaceData.selectedFuel || Object.keys(furnaceData.selectedOres).length === 0) return;
         
         // Calcular tiempo total basado en las cantidades seleccionadas
         let totalTime = 0;
         for (const [ore, amount] of Object.entries(furnaceData.selectedOres)) {
             const rule = furnaceData.smeltingRules[ore];
             if (rule) {
                 totalTime += rule.time * amount;
             }
         }
         
         // Enviar al servidor
         fetch(`https://${GetParentResourceName()}/startSmelting`, {
             method: 'POST',
             headers: {
                 'Content-Type': 'application/json; charset=UTF-8',
             },
             body: JSON.stringify({
                 selectedItems: furnaceData.selectedOres,
                 fuelAmount: furnaceData.selectedFuelAmount,
                 fuelType: furnaceData.selectedFuel,
                 totalTime: totalTime
             })
         });
     }

     function showProgress(totalTime) {
         const progressContainer = document.getElementById('progressContainer');
         const progressFill = document.getElementById('progressFill');
         const progressText = document.getElementById('progressText');
         
         progressContainer.classList.add('show');
         
         let elapsed = 0;
         const interval = setInterval(() => {
             elapsed += 100;
             const progress = Math.min((elapsed / totalTime) * 100, 100);
             
             progressFill.style.width = progress + '%';
             progressText.textContent = Math.floor(progress) + '%';
             
             if (elapsed >= totalTime) {
                 clearInterval(interval);
                 setTimeout(() => {
                     progressContainer.classList.remove('show');
                     closeFurnace();
                 }, 500);
             }
         }, 100);
     }

     function takeOre() {
         fetch(`https://${GetParentResourceName()}/takeOre`, {
             method: 'POST',
             headers: {
                 'Content-Type': 'application/json; charset=UTF-8',
             },
             body: JSON.stringify({})
         });
     }

     function takeAll() {
         fetch(`https://${GetParentResourceName()}/takeAll`, {
             method: 'POST',
             headers: {
                 'Content-Type': 'application/json; charset=UTF-8',
             },
             body: JSON.stringify({})
         });
     }

     function closeFurnace() {
         fetch(`https://${GetParentResourceName()}/closeSmelting`, {
             method: 'POST',
             headers: {
                 'Content-Type': 'application/json; charset=UTF-8',
             },
             body: JSON.stringify({})
         });
     }

     function formatItemName(name) {
         return name.replace(/_/g, ' ').replace(/\b\w/g, l => l.toUpperCase());
     }

     // Cerrar con ESC
     document.addEventListener('keydown', function(event) {
         if (event.key === 'Escape') {
             closeFurnace();
         }
     });

     // Cerrar selector de combustible al hacer clic fuera
     document.addEventListener('click', function(event) {
         const fuelSlot = document.getElementById('fuelSlot');
         const fuelSelector = document.getElementById('fuelSelector');
         
         if (!fuelSlot.contains(event.target)) {
             fuelSelector.classList.remove('show');
         }
     });
