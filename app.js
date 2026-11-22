/* STOCKPRO demo MVP: datos locales al navegador; no autentica ni sincroniza. */
(() => {
  'use strict';
  const STORAGE_KEY = 'stockpro.single-store.demo.v1';
  const seed = () => {
    const ids = () => crypto.randomUUID ? crypto.randomUUID() : `${Date.now()}-${Math.random().toString(16).slice(2)}`;
    const p1=ids(),p2=ids(),p3=ids(),p4=ids();
    const products = [
      {id:p1,name:'Remera Essential',category:'Indumentaria',sku:'REM-001',price:18500,active:true,variants:[{id:ids(),size:'S',color:'Negro',stock:8},{id:ids(),size:'M',color:'Negro',stock:4},{id:ids(),size:'L',color:'Blanco',stock:2}]},
      {id:p2,name:'Jean Slim Fit',category:'Indumentaria',sku:'JEA-014',price:42000,active:true,variants:[{id:ids(),size:'38',color:'Azul',stock:5},{id:ids(),size:'40',color:'Azul',stock:3}]},
      {id:p3,name:'Zapatilla Urban',category:'Calzado',sku:'ZAP-203',price:58900,active:true,variants:[{id:ids(),size:'38',color:'Blanco',stock:2},{id:ids(),size:'39',color:'Negro',stock:6}]},
      {id:p4,name:'Gorra Classic',category:'Accesorios',sku:'GOR-010',price:12500,active:true,variants:[{id:ids(),size:'Único',color:'Verde',stock:7}]}
    ];
    const now = new Date();
    const demoSale = {id:ids(),createdAt:new Date(now.getTime()-3600000).toISOString(),note:'Venta de ejemplo',total:18500,items:[{productId:p1,productName:'Remera Essential',size:'S',color:'Negro',quantity:1,unitPrice:18500,sku:'REM-001'}]};
    products[0].variants[0].stock -= 1;
    return {products,sales:[demoSale]};
  };
  const safeLoad = () => {
    try {
      const raw = localStorage.getItem(STORAGE_KEY);
      if (!raw) return seed();
      const data = JSON.parse(raw);
      if (!Array.isArray(data.products) || !Array.isArray(data.sales)) return seed();
      return data;
    } catch { return seed(); }
  };
  let db = safeLoad();
  let cart = [];
  const $ = (selector, root=document) => root.querySelector(selector);
  const $$ = (selector, root=document) => [...root.querySelectorAll(selector)];
  const esc = (v='') => String(v).replace(/[&<>"']/g, ch => ({'&':'&amp;','<':'&lt;','>':'&gt;','"':'&quot;',"'":'&#39;'}[ch]));
  const money = n => new Intl.NumberFormat('es-AR',{style:'currency',currency:'ARS',maximumFractionDigits:2}).format(Number(n)||0);
  const stockOf = p => p.variants.reduce((sum,v)=>sum+(Number(v.stock)||0),0);
  const save = () => { localStorage.setItem(STORAGE_KEY, JSON.stringify(db)); renderAll(); };
  const toast = message => {
    const box=$('#toast'); box.textContent=message; box.classList.add('show');
    clearTimeout(toast.timer); toast.timer=setTimeout(()=>box.classList.remove('show'),3200);
  };
  const dateLabel = iso => new Intl.DateTimeFormat('es-AR',{dateStyle:'short',timeStyle:'short'}).format(new Date(iso));

  function renderDashboard(){
    $('#statProducts').textContent=db.products.filter(p=>p.active).length;
    $('#statSales').textContent=db.sales.length;
    $('#statStock').textContent=db.products.reduce((sum,p)=>sum+stockOf(p),0);
    $('#statRevenue').textContent=money(db.sales.reduce((sum,s)=>sum+s.total,0));
    const lows=db.products.flatMap(p=>p.variants.filter(v=>v.stock<=3).map(v=>({p,v}))).sort((a,b)=>a.v.stock-b.v.stock);
    $('#lowStockFoot').textContent=`${lows.length} variante${lows.length===1?'':'s'} con 3 unidades o menos`;
    $('#lowStockList').innerHTML=lows.length?lows.slice(0,5).map(({p,v})=>`<div class="stock-item"><span class="product-thumb">${p.category==='Calzado'?'👟':p.category==='Accesorios'?'🧢':'👕'}</span><span class="product-info"><b>${esc(p.name)}</b><small>${esc(v.size)} · ${esc(v.color)}</small></span><span class="stock-count ${v.stock<=1?'critical':''}">${v.stock} <small>un.</small></span></div>`).join(''):'<p class="muted empty-inline">No hay variantes con stock bajo.</p>';
    const sales=[...db.sales].sort((a,b)=>new Date(b.createdAt)-new Date(a.createdAt)).slice(0,4);
    $('#recentSales').innerHTML=sales.length?`<div class="table-wrap"><table><thead><tr><th>FECHA</th><th>ARTÍCULOS</th><th>NOTA</th><th>TOTAL</th></tr></thead><tbody>${sales.map(s=>`<tr><td>${dateLabel(s.createdAt)}</td><td>${s.items.reduce((n,i)=>n+i.quantity,0)}</td><td>${esc(s.note||'—')}</td><td class="amount">${money(s.total)}</td></tr>`).join('')}</tbody></table></div>`:'<p class="muted empty-inline">Todavía no registraste ventas.</p>';
  }
  function renderProducts(){
    const q=$('#productSearch').value.trim().toLocaleLowerCase('es-AR');
    const filtered=db.products.filter(p=>`${p.name} ${p.category} ${p.sku}`.toLocaleLowerCase('es-AR').includes(q));
    $('#productCount').textContent=`${filtered.length} de ${db.products.length}`;
    $('#emptyProducts').hidden=filtered.length>0;
    $('#productRows').innerHTML=filtered.map(p=>`<tr><td><span class="table-product"><span class="tiny-product">${p.category==='Calzado'?'👟':p.category==='Accesorios'?'🧢':'👕'}</span><span><b>${esc(p.name)}</b><small>${esc(p.sku||'Sin SKU')}</small></span></span></td><td>${esc(p.category||'—')}</td><td class="amount">${money(p.price)}</td><td><div class="variant-list">${p.variants.map(v=>`<span class="variant-chip">${esc(v.size)} · ${esc(v.color)} <b>${v.stock}</b></span>`).join('')}</div><small class="muted">${stockOf(p)} unidades</small></td><td><span class="status ${p.active?'ok':'off'}">${p.active?'Activo':'Archivado'}</span></td><td><button class="small-button" data-edit="${esc(p.id)}" type="button">Editar</button></td></tr>`).join('');
  }
  function renderVariantSelect(){
    const select=$('#saleVariant'); const previous=select.value;
    const choices=db.products.filter(p=>p.active).flatMap(p=>p.variants.map(v=>({p,v}))).filter(x=>x.v.stock>0);
    select.innerHTML=choices.length?'<option value="">Elegí producto, talle y color</option>'+choices.map(({p,v})=>`<option value="${esc(v.id)}">${esc(p.name)} · ${esc(v.size)} / ${esc(v.color)} · ${money(p.price)} · stock ${v.stock}</option>`).join(''):'<option value="">No hay variantes con stock disponible</option>';
    if(choices.some(x=>x.v.id===previous))select.value=previous;
    updateAvailable();
  }
  function updateAvailable(){
    const found=db.products.flatMap(p=>p.variants.map(v=>({p,v}))).find(x=>x.v.id===$('#saleVariant').value);
    $('#availableStock').textContent=found?`Disponible: ${found.v.stock} unidades`:'Seleccioná una variante';
    $('#saleQuantity').max=found?found.v.stock:1;
  }
  function renderCart(){
    const count=cart.reduce((sum,item)=>sum+item.quantity,0); const total=cart.reduce((sum,item)=>sum+item.quantity*item.unitPrice,0);
    $('#cartCount').textContent=`${count} artículo${count===1?'':'s'}`; $('#cartTotal').textContent=money(total); $('#confirmSale').disabled=count===0;
    $('#cartItems').innerHTML=cart.length?cart.map((item,index)=>`<div class="cart-item"><div><b>${esc(item.productName)}</b><small>${esc(item.size)} · ${esc(item.color)} · ${item.quantity} × ${money(item.unitPrice)}</small></div><b>${money(item.quantity*item.unitPrice)}</b><button type="button" class="remove-button" data-remove-cart="${index}" aria-label="Quitar ${esc(item.productName)}">×</button></div>`).join(''):'<div class="empty-cart"><span>🛒</span><b>El carrito está vacío</b><small>Agregá una variante para comenzar.</small></div>';
  }
  function renderSales(){
    const sales=[...db.sales].sort((a,b)=>new Date(b.createdAt)-new Date(a.createdAt));
    $('#emptySales').hidden=sales.length>0;
    $('#salesRows').innerHTML=sales.map(s=>`<tr><td>${dateLabel(s.createdAt)}</td><td>${s.items.reduce((n,i)=>n+i.quantity,0)}</td><td><div class="sale-detail">${s.items.map(i=>`${esc(i.productName)} · ${esc(i.size)} ${esc(i.color)} × ${i.quantity}`).join('<br>')}</div></td><td>${esc(s.note||'—')}</td><td class="amount">${money(s.total)}</td></tr>`).join('');
  }
  function renderCatalog(){
    const products=db.products.filter(p=>p.active&&p.variants.some(v=>v.stock>0));
    $('#emptyCatalog').hidden=products.length>0;
    $('#catalogGrid').innerHTML=products.map(p=>`<article class="catalog-card"><div class="catalog-image">${p.category==='Calzado'?'👟':p.category==='Accesorios'?'🧢':'👕'}</div><div class="catalog-card-body"><span class="category-tag">${esc(p.category||'Producto')}</span><h2>${esc(p.name)}</h2><p class="catalog-sku">${esc(p.sku||'')}</p><b class="catalog-price">${money(p.price)}</b><div class="catalog-variants">${p.variants.filter(v=>v.stock>0).map(v=>`<span>${esc(v.size)} / ${esc(v.color)}</span>`).join('')}</div><small class="available-label">Disponible para consultar</small></div></article>`).join('');
  }
  function renderAll(){renderDashboard();renderProducts();renderVariantSelect();renderCart();renderSales();renderCatalog();}

  function go(view){
    if(!$('#view-'+view))view='inicio';
    $$('.view').forEach(section=>section.classList.toggle('active',section.id==='view-'+view));
    $$('.nav-link[data-view]').forEach(link=>link.classList.toggle('active',link.dataset.view===view));
    $('#crumb').textContent=$('#view-'+view).dataset.title;
    $('#sidebar').classList.remove('open');$('#mobileMenu').setAttribute('aria-expanded','false');
    if(location.hash!==`#${view}`)history.replaceState(null,'',`#${view}`);
    window.scrollTo({top:0,behavior:'smooth'});
  }
  function addVariantRow(values={}){
    const row=document.createElement('div');row.className='variant-row';row.dataset.id=values.id||'';
    row.innerHTML=`<input class="variant-size" aria-label="Talle" maxlength="20" placeholder="M" value="${esc(values.size||'')}" required><input class="variant-color" aria-label="Color" maxlength="30" placeholder="Negro" value="${esc(values.color||'')}" required><input class="variant-stock" aria-label="Unidades en stock" type="number" inputmode="numeric" min="0" step="1" value="${Number.isInteger(values.stock)?values.stock:0}" required><button class="remove-variant" type="button" aria-label="Quitar variante">×</button>`;
    $('#variantEditor').append(row);
  }
  function openProduct(product=null){
    $('#productForm').reset();$('#variantEditor').innerHTML='';$('#editingProductId').value=product?.id||'';
    $('#dialogTitle').textContent=product?'Editar producto':'Nuevo producto';
    $('#productName').value=product?.name||'';$('#productCategory').value=product?.category||'';$('#productPrice').value=product?.price??'';$('#productSku').value=product?.sku||'';$('#productActive').checked=product?product.active:true;
    (product?.variants?.length?product.variants:[{}]).forEach(v=>addVariantRow(v));
    $('#productDialog').showModal();
  }
  $('#todayLabel').textContent=new Intl.DateTimeFormat('es-AR',{weekday:'long',day:'numeric',month:'long',year:'numeric'}).format(new Date()).toLocaleUpperCase('es-AR');
  $('#mobileMenu').addEventListener('click',()=>{const open=$('#sidebar').classList.toggle('open');$('#mobileMenu').setAttribute('aria-expanded',String(open));});
  $$('.nav-link[data-view]').forEach(a=>a.addEventListener('click',e=>{e.preventDefault();go(a.dataset.view);}));
  $$('[data-go]').forEach(b=>b.addEventListener('click',()=>go(b.dataset.go)));
  $('#productSearch').addEventListener('input',renderProducts);
  $('#addProduct').addEventListener('click',()=>openProduct());
  $('#addVariant').addEventListener('click',()=>addVariantRow());
  $('#variantEditor').addEventListener('click',e=>{if(e.target.closest('.remove-variant')){if($$('.variant-row','#variantEditor').length>1)e.target.closest('.variant-row').remove();else toast('El producto necesita al menos una variante.');}});
  $('#productRows').addEventListener('click',e=>{const button=e.target.closest('[data-edit]');if(button){const product=db.products.find(p=>p.id===button.dataset.edit);if(product)openProduct(product);}});
  $('#productForm').addEventListener('submit',e=>{
    e.preventDefault();
    const rows=$$('.variant-row','#variantEditor');
    const variants=rows.map(row=>({id:row.dataset.id||'',size:$('.variant-size',row).value.trim(),color:$('.variant-color',row).value.trim(),stock:Number($('.variant-stock',row).value)}));
    if(variants.some(v=>!v.size||!v.color||!Number.isInteger(v.stock)||v.stock<0)){toast('Revisá talle, color y cantidad de cada variante.');return;}
    const editing=$('#editingProductId').value;const old=db.products.find(p=>p.id===editing);
    const updated={id:old?.id||`${Date.now()}-${Math.random().toString(16).slice(2)}`,name:$('#productName').value.trim(),category:$('#productCategory').value.trim()||'General',sku:$('#productSku').value.trim(),price:Number($('#productPrice').value),active:$('#productActive').checked,variants:variants.map(v=>({id:v.id||`${Date.now()}-${Math.random().toString(16).slice(2)}`,size:v.size,color:v.color,stock:v.stock}))};
    if(!updated.name||!Number.isFinite(updated.price)||updated.price<=0){toast('Ingresá nombre y un precio mayor a cero.');return;}
    if(old)db.products=db.products.map(p=>p.id===old.id?updated:p);else db.products.unshift(updated);
    $('#productDialog').close();save();toast(old?'Producto actualizado.':'Producto agregado.');
  });
  $('#saleVariant').addEventListener('change',updateAvailable);
  $('#cartForm').addEventListener('submit',e=>{
    e.preventDefault();const variantId=$('#saleVariant').value;const found=db.products.flatMap(p=>p.variants.map(v=>({p,v}))).find(x=>x.v.id===variantId);const qty=Number($('#saleQuantity').value);
    if(!found||!Number.isInteger(qty)||qty<1){toast('Elegí una variante y una cantidad válida.');return;}
    const already=cart.filter(i=>i.variantId===variantId).reduce((n,i)=>n+i.quantity,0);
    if(qty+already>found.v.stock){toast(`Stock insuficiente. Hay ${found.v.stock} unidad(es) disponible(s).`);return;}
    const existing=cart.find(i=>i.variantId===variantId);
    if(existing)existing.quantity+=qty;else cart.push({variantId,productId:found.p.id,productName:found.p.name,sku:found.p.sku,size:found.v.size,color:found.v.color,quantity:qty,unitPrice:found.p.price});
    $('#saleQuantity').value=1;renderCart();toast('Agregado al carrito.');
  });
  $('#cartItems').addEventListener('click',e=>{const button=e.target.closest('[data-remove-cart]');if(button){cart.splice(Number(button.dataset.removeCart),1);renderCart();}});
  $('#clearCart').addEventListener('click',()=>{cart=[];renderCart();});
  $('#confirmSale').addEventListener('click',()=>{
    if(!cart.length)return;
    for(const item of cart){const p=db.products.find(x=>x.id===item.productId);const v=p?.variants.find(x=>x.id===item.variantId);if(!p?.active||!v||v.stock<item.quantity){toast('Cambió el stock disponible. Revisá el carrito antes de confirmar.');renderAll();return;}}
    for(const item of cart){const v=db.products.find(p=>p.id===item.productId).variants.find(x=>x.id===item.variantId);v.stock-=item.quantity;}
    const sale={id:`${Date.now()}-${Math.random().toString(16).slice(2)}`,createdAt:new Date().toISOString(),note:$('#saleNote').value.trim(),items:cart.map(({variantId,...item})=>({...item})),total:cart.reduce((sum,i)=>sum+i.quantity*i.unitPrice,0)};
    db.sales.push(sale);cart=[];$('#saleNote').value='';save();go('historial');toast('Venta registrada y stock descontado.');
  });
  $('#resetDemo').addEventListener('click',()=>{if(confirm('¿Restaurar los datos iniciales de ejemplo? Se borrarán los cambios y ventas guardados en este navegador.')){db=seed();cart=[];save();go('inicio');toast('Demo restaurada.');}});
  $$('[data-close-dialog]').forEach(button=>button.addEventListener('click',()=>button.closest('dialog').close()));
  window.addEventListener('hashchange',()=>go(location.hash.slice(1)));
  go(location.hash.slice(1)||'inicio');renderAll();
})();
