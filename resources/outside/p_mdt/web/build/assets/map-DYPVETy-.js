import{j as o,B as E,aj as L,t as U,F as O,n as T,A as X,D as Y,i as w}from"./mantine-uy5lBGry.js";import{r as i}from"./react-nPrKd0zk.js";import{L as a}from"./leaflet-BG0iU5o3.js";import{c as G}from"./dispatch-C5SkMRhQ.js";import{b as J,u as K,a as Q,f as j,i as F}from"./index-BAGEaU1x.js";import{x as _,w as H,R as D,v as W}from"./tabler-DUj1lYm8.js";const ee=u=>`
    <span style="
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 2.5rem;
        height: 2.5rem;
        border-radius: 50%;
        background: ${u};
        color: white;
        font-weight: bold;
        font-size: 1rem;
        box-shadow: 0 2px 8px rgba(0,0,0,0.15);
        border: .0625rem solid #fff;
    ">
    </span>
`,re=u=>`
    <span style="
        display: inline-flex;
        align-items: center;
        justify-content: center;
        width: 1.5rem;
        height: 1.5rem;
        border-radius: 50%;
        background: rgba(10, 70, 200, 0.75);
        color: white;
        font-weight: bold;
        font-size: .675rem;
        box-shadow: 0 .25rem .5rem rgba(0,0,0,0.15);
        border: .0625rem solid #fff;
    ">
    ${u}
    </span>
`,N={high:"rgba(255, 0, 0, 0.5)",medium:"rgba(255, 128, 0, 0.5)",low:"rgba(0, 128, 0, 0.5)"},y=(u,p)=>[p,u],te=({focusedCall:u,onFocusHandled:p})=>{J();const{permissions:v,locales:m,dispatchData:r,playerData:Z}=K(),k=i.useRef(null),s=i.useRef(null),f=i.useRef({}),g=i.useRef({}),[S,B]=i.useState(!0),[z,M]=i.useState(!0),[t,h]=i.useState(null),[C,A]=i.useState(null),I=i.useRef(!1),R=i.useMemo(()=>a.extend({},a.CRS.Simple,{projection:a.Projection.LonLat,scale:c=>Math.pow(2,c),zoom:c=>Math.log(c)/.6931471805599453,distance:(c,x)=>{const b=x.lng-c.lng,d=x.lat-c.lat;return Math.sqrt(b*b+d*d)},transformation:new a.Transformation(.02072,117.3,-.0205,172.8),infinite:!0}),[]),$=i.useCallback(n=>{if(s.current&&(r!=null&&r.calls)){const e=r.calls.find(l=>l.id===n);if(e){const[l,c]=y(e.location.coords.x,e.location.coords.y);s.current.setView([l,c],4,{animate:!0}),h(e)}else A(n)}else A(n)},[r==null?void 0:r.calls]);Q("viewAlert",$),i.useEffect(()=>{if(C!==null&&s.current&&(r!=null&&r.calls)){const n=r.calls.find(e=>e.id===C);if(n){const[e,l]=y(n.location.coords.x,n.location.coords.y);s.current.setView([e,l],4,{animate:!0}),h(n),A(null)}}},[r==null?void 0:r.calls,C]),i.useEffect(()=>{if(k.current&&!I.current){I.current=!0,s.current=a.map(k.current,{crs:R,minZoom:2,maxZoom:5,zoom:2,preferCanvas:!0,center:[0,0],zoomControl:!0,scrollWheelZoom:!0,doubleClickZoom:!0,boxZoom:!0,keyboard:!0,dragging:!0,touchZoom:!0,attributionControl:!1,renderer:a.canvas()});const n=F()?"../../../../tiles":"web/tiles";a.tileLayer(`${n}/{z}/{x}/{y}.jpg`,{minZoom:2,maxZoom:5,noWrap:!0,attribution:"",id:"AtlasStyle map",errorTileUrl:`${n}/empty.jpg`,updateWhenIdle:!0,updateWhenZooming:!1,keepBuffer:4}).addTo(s.current);const l=a.latLngBounds(a.latLng(-4e3,-4200),a.latLng(8200,5500));s.current.setMaxBounds(l),s.current.on("drag",function(){s.current.panInsideBounds(l,{animate:!1})})}return()=>{s.current&&(Object.values(f.current).forEach(n=>{var e;return(e=s.current)==null?void 0:e.removeLayer(n)}),Object.values(g.current).forEach(n=>{var e;return(e=s.current)==null?void 0:e.removeLayer(n)}),f.current={},g.current={},s.current.remove(),s.current=null,I.current=!1)}},[R]),i.useEffect(()=>{if(u&&s.current){const[n,e]=y(u.location.coords.x,u.location.coords.y);s.current.setView([n,e],4,{animate:!0}),h(u),p==null||p()}},[u,p]),i.useEffect(()=>{if(!s.current||!t)return;const n=r==null?void 0:r.calls.find(e=>e.id===t.id);h(n||null)},[r==null?void 0:r.calls,t==null?void 0:t.id]),i.useEffect(()=>{if(!s.current)return;if(!z){Object.values(f.current).forEach(e=>{var l;return(l=s.current)==null?void 0:l.removeLayer(e)}),f.current={};return}if(!(r!=null&&r.calls))return;const n=new Set(r.calls.map(e=>e.id));Object.entries(f.current).forEach(([e,l])=>{var c;n.has(Number(e))||((c=s.current)==null||c.removeLayer(l),delete f.current[Number(e)])}),r.calls.forEach(e=>{if(!f.current[e.id]){const[c,x]=y(e.location.coords.x,e.location.coords.y),b=N[e.priority]||N.low,d=a.marker([c,x],{icon:a.divIcon({className:"dispatch-marker",html:ee(b),iconSize:[32,32],iconAnchor:[16,16]})});d.addTo(s.current),d.on("click",()=>h(e)),f.current[e.id]=d}})},[r==null?void 0:r.calls,z]),i.useEffect(()=>{if(!s.current)return;if(!S){Object.values(g.current).forEach(e=>{var l;return(l=s.current)==null?void 0:l.removeLayer(e)}),g.current={};return}if(!(r!=null&&r.units))return;const n=new Set(r.units.map(e=>e.callsign||e.player));Object.entries(g.current).forEach(([e,l])=>{var c;n.has(e)||((c=s.current)==null||c.removeLayer(l),delete g.current[e])}),r.units.forEach(e=>{const l=e.callsign||e.player,c=g.current[l],[x,b]=y(e.location.x,e.location.y);if(c)c.setLatLng([x,b]);else{const d=a.marker([x,b],{icon:a.divIcon({className:"officer-marker",html:re(e.callsign?e.callsign.slice(-3):"N/A"),iconSize:[18,18],iconAnchor:[9,9]})});d.addTo(s.current),d.bindPopup(`
                    <div>
                        <strong>${e.callsign||"N/A"}</strong><br/>
                        ${e.player}<br/>
                        <small>Street: ${e.street}</small><br/>
                        <small>Out of vehicle</small>
                    </div>
                `),g.current[l]=d}})},[r==null?void 0:r.units,S]);const P=i.useCallback(n=>{B(n.currentTarget.checked)},[]),V=i.useCallback(n=>{M(n.currentTarget.checked)},[]),q=i.useCallback(()=>{h(null)},[]);return o.jsx(E,{style:{height:"100%",width:"100%",position:"relative"},children:o.jsxs("div",{ref:k,style:{height:"100%",width:"100%",borderRadius:".5rem",overflow:"hidden",border:".0625rem solid rgba(255, 255, 255, .25)"},children:[o.jsxs(E,{className:G.dispatchToggleWrapper,children:[o.jsx(L,{size:"xs",label:m.toggle_officers,checked:S,onChange:P}),o.jsx(L,{size:"xs",mt:"xs",label:m.toggle_calls,checked:z,onChange:V})]}),o.jsx(U,{mounted:t!==null,timingFunction:"ease",duration:300,transition:"slide-right",children:n=>o.jsxs(E,{style:{...n,position:"absolute",bottom:".75rem",left:".75rem",background:"rgba(0, 0, 0, 0.8)",padding:"1.25rem",borderRadius:".5rem",zIndex:1e3},children:[o.jsxs(O,{align:"center",justify:"space-between",gap:"2rem",children:[o.jsxs(O,{direction:"column",gap:".1rem",children:[o.jsx(T,{style:{maxWidth:"12.5rem",textOverflow:"ellipsis",whiteSpace:"nowrap",overflow:"hidden"},fw:600,lts:.25,size:"sm",children:(t==null?void 0:t.title)||m.unknown_title}),o.jsx(T,{style:{maxWidth:"12.5rem",textOverflow:"ellipsis",whiteSpace:"nowrap",overflow:"hidden"},size:"xs",c:"dimmed",children:(t==null?void 0:t.description)||m.no_description})]}),o.jsx(X,{onClick:q,variant:"light",color:"gray",size:"2rem",children:o.jsx(_,{size:"1.15rem",stroke:1.5})})]}),o.jsx(Y,{my:"sm",opacity:.5}),o.jsxs(O,{gap:"xs",children:[t!=null&&t.units.find(e=>e.identifier===Z.id)?o.jsx(w,{onClick:()=>t&&j("cancelAlert",{id:t.id}),fullWidth:!0,leftSection:o.jsx(_,{stroke:1.5,size:"1rem"}),size:"xs",color:"red",variant:"light",children:m.cancel}):o.jsx(w,{onClick:()=>t&&j("acceptAlert",{id:t.id}),fullWidth:!0,leftSection:o.jsx(H,{stroke:1.5,size:"1rem"}),size:"xs",color:"green",variant:"light",children:m.accept}),t!=null&&t.canAnswer?o.jsx(w,{disabled:!v["dispatch.respond_call"],onClick:()=>t&&j("respondAlert",{id:t.id}),fullWidth:!0,leftSection:o.jsx(D,{stroke:1.5,size:"1rem"}),size:"xs",color:"teal",variant:"light",children:m.respond}):o.jsx(w,{disabled:!v["dispatch.delete_call"],onClick:()=>t&&j("deleteAlert",{id:t.id}),fullWidth:!0,leftSection:o.jsx(W,{stroke:1.5,size:"1rem"}),size:"xs",color:"blue",variant:"light",children:m.delete})]}),(t==null?void 0:t.canAnswer)&&o.jsx(w,{disabled:!v["dispatch.delete_call"],onClick:()=>t&&j("deleteAlert",{id:t.id}),fullWidth:!0,mt:"xs",leftSection:o.jsx(W,{stroke:1.5,size:"1rem"}),size:"xs",color:"blue",variant:"light",children:m.delete})]})})]})})},ae=i.memo(te);export{ae as default};
