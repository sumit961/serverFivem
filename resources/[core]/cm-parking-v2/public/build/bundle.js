var app=function(){"use strict";function n(){}function t(n){return n()}function e(){return Object.create(null)}function i(n){n.forEach(t)}function o(n){return"function"==typeof n}function s(n,t){return n!=n?t==t:n!==t||n&&"object"==typeof n||"function"==typeof n}function a(n,t){n.appendChild(t)}function d(n,t,e){n.insertBefore(t,e||null)}function r(n){n.parentNode.removeChild(n)}function l(n){return document.createElement(n)}function c(n){return document.createTextNode(n)}function w(){return c(" ")}function p(n,t,e,i){return n.addEventListener(t,e,i),()=>n.removeEventListener(t,e,i)}function h(n,t,e){null==e?n.removeAttribute(t):n.getAttribute(t)!==e&&n.setAttribute(t,e)}function u(n,t){t=""+t,n.wholeText!==t&&(n.data=t)}let f;function $(n){f=n}const g=[],v=[],m=[],k=[],b=Promise.resolve();let y=!1;function x(n){m.push(n)}const C=new Set;let z=0;function I(){const n=f;do{for(;z<g.length;){const n=g[z];z++,$(n),S(n.$$)}for($(null),g.length=0,z=0;v.length;)v.pop()();for(let n=0;n<m.length;n+=1){const t=m[n];C.has(t)||(C.add(t),t())}m.length=0}while(g.length);for(;k.length;)k.pop()();y=!1,C.clear(),$(n)}function S(n){if(null!==n.fragment){n.update(),i(n.before_update);const t=n.dirty;n.dirty=[-1],n.fragment&&n.fragment.p(n.ctx,t),n.after_update.forEach(x)}}const O=new Set;function _(n,t){-1===n.$$.dirty[0]&&(g.push(n),y||(y=!0,b.then(I)),n.$$.dirty.fill(0)),n.$$.dirty[t/31|0]|=1<<t%31}function A(s,a,d,l,c,w,p,h=[-1]){const u=f;$(s);const g=s.$$={fragment:null,ctx:null,props:w,update:n,not_equal:c,bound:e(),on_mount:[],on_destroy:[],on_disconnect:[],before_update:[],after_update:[],context:new Map(a.context||(u?u.$$.context:[])),callbacks:e(),dirty:h,skip_bound:!1,root:a.target||u.$$.root};p&&p(g.root);let v=!1;if(g.ctx=d?d(s,a.props||{},((n,t,...e)=>{const i=e.length?e[0]:t;return g.ctx&&c(g.ctx[n],g.ctx[n]=i)&&(!g.skip_bound&&g.bound[n]&&g.bound[n](i),v&&_(s,n)),t})):[],g.update(),v=!0,i(g.before_update),g.fragment=!!l&&l(g.ctx),a.target){if(a.hydrate){const n=function(n){return Array.from(n.childNodes)}(a.target);g.fragment&&g.fragment.l(n),n.forEach(r)}else g.fragment&&g.fragment.c();a.intro&&((m=s.$$.fragment)&&m.i&&(O.delete(m),m.i(k))),function(n,e,s,a){const{fragment:d,on_mount:r,on_destroy:l,after_update:c}=n.$$;d&&d.m(e,s),a||x((()=>{const e=r.map(t).filter(o);l?l.push(...e):i(e),n.$$.on_mount=[]})),c.forEach(x)}(s,a.target,a.anchor,a.customElement),I()}var m,k;$(u)}function N(n,t,e){const i=n.slice();return i[23]=t[e],i[25]=e,i}function P(n){let t,e,i,o,s,f,$,g,v,m=n[23].Label+"";function k(){return n[11](n[25],n[23])}return{c(){t=l("div"),e=l("input"),i=w(),o=l("label"),s=l("p"),f=c(m),$=w(),h(e,"class","dialog-checked svelte-irn2rz"),h(e,"id","vehicle-"+n[25]),h(e,"type","radio"),h(s,"class","svelte-irn2rz"),h(o,"for","vehicle-"+n[25]),h(o,"class","svelte-irn2rz"),h(t,"class","dialog-list-item svelte-irn2rz")},m(n,r){d(n,t,r),a(t,e),a(t,i),a(t,o),a(o,s),a(s,f),a(t,$),g||(v=p(e,"click",k),g=!0)},p(t,e){n=t,64&e&&m!==(m=n[23].Label+"")&&u(f,m)},d(n){n&&r(t),g=!1,v()}}}function E(t){let e,o,s,f,$,g,v,m,k,b,y,x,C,z,I,S,O,_,A,E,L,F,D,M,Y,B,J,T,j,V,q,H,G,K,Q,R,U,W,X,Z,nn,tn,en,on,sn,an,dn,rn,ln,cn,wn,pn,hn,un,fn,$n,gn,vn,mn=Math.round(t[0].length/10)+"",kn=t[6],bn=[];for(let n=0;n<kn.length;n+=1)bn[n]=P(N(t,kn,n));return{c(){e=l("main"),o=l("div"),s=l("i"),f=w(),$=l("div"),g=l("h1"),v=c(t[2]),m=l("span"),m.textContent="Parking is given for 24 hours",k=w(),b=l("div"),y=l("h1"),x=c("Free spaces"),C=l("span"),z=c(t[4]),I=w(),S=l("h1"),O=c("Cost per space"),_=l("span"),A=c(t[3]),E=c("$"),L=w(),F=l("h1"),D=c("Balance"),M=l("span"),Y=c(t[5]),B=c("$"),J=w(),T=l("div"),j=l("div"),V=l("p"),V.textContent="Select Vehicle",q=w(),H=l("div");for(let n=0;n<bn.length;n+=1)bn[n].c();G=w(),K=l("div"),Q=l("button"),Q.textContent="Confirm",R=w(),U=l("button"),U.textContent="Cancel",W=w(),X=l("div"),Z=w(),nn=l("div"),tn=l("div"),en=w(),on=l("div"),sn=w(),an=l("div"),dn=l("span"),rn=c(t[1]),ln=c(" / "),cn=c(mn),wn=w(),pn=l("div"),hn=w(),un=l("div"),un.innerHTML='<div class="parking-footer-left svelte-irn2rz"></div> \n\t\t\t<div class="parking-footer-right svelte-irn2rz"><button id="callCar" class="b-blue svelte-irn2rz">Call Your Car</button> \n\t\t\t\t<button id="cancel" class="b-cancel svelte-irn2rz">Cancel Parking</button> \n\t\t\t\t<button id="buySpot" class="b-blue svelte-irn2rz">Buy Location</button></div>',fn=w(),$n=l("div"),h(s,"class","parking-bg-image svelte-irn2rz"),h(m,"class","svelte-irn2rz"),h(g,"class","svelte-irn2rz"),h(C,"class","svelte-irn2rz"),h(y,"class","svelte-irn2rz"),h(_,"class","svelte-irn2rz"),h(S,"class","svelte-irn2rz"),h(M,"class","svelte-irn2rz"),h(F,"class","svelte-irn2rz"),h(b,"class","parking-header-right svelte-irn2rz"),h($,"class","parking-header svelte-irn2rz"),h(V,"class","dialog-box-header svelte-irn2rz"),h(H,"class","dialog-list svelte-irn2rz"),h(Q,"class","b-yellow svelte-irn2rz"),h(U,"class","b-white svelte-irn2rz"),h(K,"class","dialog-buttons svelte-irn2rz"),h(j,"class","dialog-box svelte-irn2rz"),h(X,"class","parking-content-arrow-left svelte-irn2rz"),h(tn,"id","list-1"),h(tn,"class","parking-main-content-line svelte-irn2rz"),h(on,"id","list-2"),h(on,"class","parking-main-content-line svelte-irn2rz"),h(dn,"class","svelte-irn2rz"),h(an,"class","pages svelte-irn2rz"),h(nn,"class","parking-main-content-list svelte-irn2rz"),h(pn,"class","parking-content-arrow-right svelte-irn2rz"),h(T,"class","parking-content svelte-irn2rz"),h(un,"class","parking-footer svelte-irn2rz"),h($n,"class","notification svelte-irn2rz"),h(o,"class","wrapper svelte-irn2rz"),h(e,"class","svelte-irn2rz")},m(n,i){d(n,e,i),a(e,o),a(o,s),a(o,f),a(o,$),a($,g),a(g,v),a(g,m),a($,k),a($,b),a(b,y),a(y,x),a(y,C),a(C,z),a(b,I),a(b,S),a(S,O),a(S,_),a(_,A),a(_,E),a(b,L),a(b,F),a(F,D),a(F,M),a(M,Y),a(M,B),a(o,J),a(o,T),a(T,j),a(j,V),a(j,q),a(j,H);for(let n=0;n<bn.length;n+=1)bn[n].m(H,null);a(j,G),a(j,K),a(K,Q),a(K,R),a(K,U),a(T,W),a(T,X),a(T,Z),a(T,nn),a(nn,tn),a(nn,en),a(nn,on),a(nn,sn),a(nn,an),a(an,dn),a(dn,rn),a(dn,ln),a(dn,cn),a(T,wn),a(T,pn),a(o,hn),a(o,un),a(o,fn),a(o,$n),gn||(vn=[p(Q,"click",t[12]),p(U,"click",t[13]),p(X,"click",t[14]),p(pn,"click",t[15])],gn=!0)},p(n,[t]){if(4&t&&u(v,n[2]),16&t&&u(z,n[4]),8&t&&u(A,n[3]),32&t&&u(Y,n[5]),576&t){let e;for(kn=n[6],e=0;e<kn.length;e+=1){const i=N(n,kn,e);bn[e]?bn[e].p(i,t):(bn[e]=P(i),bn[e].c(),bn[e].m(H,null))}for(;e<bn.length;e+=1)bn[e].d(1);bn.length=kn.length}2&t&&u(rn,n[1]),1&t&&mn!==(mn=Math.round(n[0].length/10)+"")&&u(cn,mn)},i:n,o:n,d(n){n&&r(e),function(n,t){for(let e=0;e<n.length;e+=1)n[e]&&n[e].d(t)}(bn,n),gn=!1,i(vn)}}}function L(n,type){window.$.post("https://cm-parking-v2/notify",JSON.stringify({message:n,type:type||"info"}))}function F(n,t,e){
    let i,o,s,a,d,r,l,c,w=[],buyMode=false,pendingAction=null,p=1,h=[],u=[];
    function showVehiclePicker(){
        pendingAction=null;
        buyMode=true;
        window.$(".dialog-confirm-msg").hide();
        window.$(".dialog-list").show();
        window.$(".dialog-box-header").text("Select Vehicle");
        window.$("#buySpot").hide();
        window.$("#callCar").hide();
        window.$("#cancel").hide();
        window.$(".parking-content-arrow-left").hide();
        window.$(".parking-content-arrow-right").hide();
        window.$(".parking-main-content-list").hide();
        window.$(".dialog-box").show();
        window.$(".dialog-list").off("click").on("click", ".dialog-list-item", function(){
            var inp = window.$(this).find("input");
            var idxStr = inp.attr("id") || "";
            var num = parseInt(idxStr.replace("vehicle-", ""), 10);
            if(!isNaN(num) && u && u[num]){
                m(num, u[num]);
                window.$(".dialog-list-item p").css({
                    background: "rgba(255, 255, 255, 0.08)",
                    color: "#ffffff",
                    borderColor: "#213b4a"
                });
                window.$(this).find("p").css({
                    background: "#00e5ff",
                    color: "#000000",
                    fontWeight: "800",
                    borderColor: "#00e5ff"
                });
            }
        });
        if(u && u.length === 1){
            m(0, u[0]);
            window.$(".dialog-list-item p").css({
                background: "#00e5ff",
                color: "#000000",
                fontWeight: "800",
                borderColor: "#00e5ff"
            });
        } else if(c) {
            window.$(l).parent().find("p").css({
                background: "#00e5ff",
                color: "#000000",
                fontWeight: "800",
                borderColor: "#00e5ff"
            });
        }
    }
    function showConfirm(act){
        pendingAction=act;
        buyMode=false;
        window.$(".dialog-box-header").text("Confirm Action");
        var loc=window.__alreadyParkedName?(" at "+window.__alreadyParkedName):"";
        var spotLabel = o ? ("Spot #" + o) : "this space";
        var msg="buy"===act?("Buy parking space "+spotLabel+" for $"+a+"?"):
               ("cancel"===act?("Cancel your current parking"+loc+" and remove vehicle from the world?"):
               ("cancelAndBuy"===act?("You have parking"+loc+". Cancel it to buy "+spotLabel+"?"):
               ("buyBusiness"===act?("Purchase this entire parking facility for " + (window.__headerData ? ("$" + Number(window.__headerData.StateValue).toLocaleString()) : "$250,000") + "?<br><span style='font-size:14px;color:#829dae;margin-top:8px;display:block;'>As the owner, you will earn 80% of all parking rentals and can manage pricing tiers ($1,000, $2,500, $5,000).</span>"):
               ("Recall your parked vehicle to "+spotLabel+"?"))));
        if(!window.$(".dialog-confirm-msg").length){
            window.$(".dialog-list").after('<div class="dialog-confirm-msg" style="display:none;font-size:18px;text-align:center;padding:25px;color:#c2d2dc;line-height:1.5;"></div>');
        }
        window.$(".dialog-list").hide();
        window.$(".dialog-confirm-msg").html(msg).show();
        window.$(".parking-content-arrow-left").hide();
        window.$(".parking-content-arrow-right").hide();
        window.$(".parking-main-content-list").hide();
        window.$(".dialog-box").show();
    }
    function f(){
        window.$("#list-1").empty();
        window.$("#list-2").empty();
        window.$("#buySpot").hide();
        window.$("#callCar").hide();
        window.$("#cancel").hide();
        e(1,p=1);
        let n=0,t=1;
        h[1]=[];
        for(let e=0;e<w.length;e++)n<10?(h[t].push(w[e]),n++):(n=0,t++,h[t]=[]);
        let s=1;
        h[1].length>5?(window.$("#list-1").show(),window.$("#list-2").show()):(window.$("#list-1").show(),window.$("#list-2").hide());
        for(let n=0;n<h[1].length;n++){
            5==n&&(s=2);
            var item=h[1][n];
            var targetList=1==s?window.$("#list-1"):window.$("#list-2");
            var spotNum=item.CoordsIdx;
            if(item.Free){
                targetList.append('<div class="parking-main-content-item" owned="false" location='+spotNum+' id="spot-'+spotNum+'"><span class="spot-tag" style="position:absolute;top:10px;font-size:0.95vw;color:#829dae;font-weight:800;letter-spacing:0.05vw;">SPOT #'+spotNum+'</span><h1>Available<span style="color:#2ecc71;">'+a+'$</span></h1></div>');
            }else if(item.IsOwner){
                targetList.append('<div class="parking-main-content-item" owned="true" location='+spotNum+' id="spot-'+spotNum+'"><span class="spot-tag" style="position:absolute;top:10px;font-size:0.95vw;color:#ffc700;font-weight:800;letter-spacing:0.05vw;">SPOT #'+spotNum+'</span><h1>Your Parking<span style="color:#ffc700;">Owned</span></h1></div>');
            }else{
                targetList.append('<div class="parking-main-content-item owned" owned="false"><span class="spot-tag" style="position:absolute;top:10px;font-size:0.95vw;color:#405766;font-weight:800;letter-spacing:0.05vw;">SPOT #'+spotNum+'</span><h1>Not Available<span>Owned</span></h1></div>');
            }
            window.$("#spot-"+spotNum).click(function(){
                o=window.$(this).attr("location");
                window.$(".selected").empty().append(i);
                i=window.$(this).html();
                if("false"==window.$(this).attr("owned")){
                    window.$(this).empty();
                    window.$(this).append('<span class="spot-tag" style="position:absolute;top:10px;font-size:0.95vw;color:#00e5ff;font-weight:800;letter-spacing:0.05vw;">SPOT #'+o+'</span><h1 style=\'color:#00e5ff;font-weight:800;\'>Selected</h1>');
                    window.$("#callCar").hide();
                    if(window.__alreadyParked){window.$("#cancel").show();}else{window.$("#cancel").hide();}
                    window.$("#buySpot").show();
                }else{
                    window.$("#buySpot").hide();
                    window.$("#callCar").show();
                    window.$("#cancel").show();
                }
                window.$(".selected").removeClass("selected");
                window.$(this).addClass("selected");
            });
        }
    }
    function $(n){
        if(h[n]){
            window.$("#list-1").empty();
            window.$("#list-2").empty();
            window.$("#buySpot").hide();
            window.$("#callCar").hide();
            window.$("#cancel").hide();
            h[n].length>5?(window.$("#list-1").show(),window.$("#list-2").show()):(window.$("#list-1").show(),window.$("#list-2").hide());
            let t=1;
            for(let e=0;e<h[n].length;e++){
                5==e&&(t=2);
                var item=h[n][e];
                var targetList=1==t?window.$("#list-1"):window.$("#list-2");
                var spotNum=item.CoordsIdx;
                if(item.Free){
                    targetList.append('<div class="parking-main-content-item" owned="false" location='+spotNum+' id="spot-'+spotNum+'"><span class="spot-tag" style="position:absolute;top:10px;font-size:0.95vw;color:#829dae;font-weight:800;letter-spacing:0.05vw;">SPOT #'+spotNum+'</span><h1>Available<span style="color:#2ecc71;">'+a+'$</span></h1></div>');
                }else if(item.IsOwner){
                    targetList.append('<div class="parking-main-content-item" owned="true" location='+spotNum+' id="spot-'+spotNum+'"><span class="spot-tag" style="position:absolute;top:10px;font-size:0.95vw;color:#ffc700;font-weight:800;letter-spacing:0.05vw;">SPOT #'+spotNum+'</span><h1>Your Parking<span style="color:#ffc700;">Owned</span></h1></div>');
                }else{
                    targetList.append('<div class="parking-main-content-item owned" owned="false"><span class="spot-tag" style="position:absolute;top:10px;font-size:0.95vw;color:#405766;font-weight:800;letter-spacing:0.05vw;">SPOT #'+spotNum+'</span><h1>Not Available<span>Owned</span></h1></div>');
                }
                window.$("#spot-"+spotNum).click(function(){
                    o=window.$(this).attr("location");
                    window.$(".selected").empty().append(i);
                    i=window.$(this).html();
                    if("false"==window.$(this).attr("owned")){
                        window.$(this).empty();
                        window.$(this).append('<span class="spot-tag" style="position:absolute;top:10px;font-size:0.95vw;color:#00e5ff;font-weight:800;letter-spacing:0.05vw;">SPOT #'+o+'</span><h1 style=\'color:#00e5ff;font-weight:800;\'>Selected</h1>');
                        window.$("#callCar").hide();
                        if(window.__alreadyParked){window.$("#cancel").show();}else{window.$("#cancel").hide();}
                        window.$("#buySpot").show();
                    }else{
                        window.$("#buySpot").hide();
                        window.$("#callCar").show();
                        window.$("#cancel").show();
                    }
                    window.$(".selected").removeClass("selected");
                    window.$(this).addClass("selected");
                });
            }
        }
    }
    function g(n){
        if(0==n){if(!h[p-1])return;e(1,p--,p),$(p);}
        else if(1==n){if(!h[p+1])return;e(1,p++,p),$(p);}
    }
    function v(){
        pendingAction=null;
        buyMode=false;
        window.$(".dialog-confirm-msg").hide();
        window.$(".dialog-list").show();
        window.$(".dialog-box-header").text("Select Vehicle");
        window.$(".dialog-box").hide();
        window.$(".parking-content-arrow-left").show();
        window.$(".parking-content-arrow-right").show();
        window.$(".parking-main-content-list").show();
        $(p);
        window.$(l).prop("checked",false);
        window.$(".dialog-list-item p").css({
            background: "rgba(255, 255, 255, 0.08)",
            color: "#ffffff",
            borderColor: "#213b4a"
        });
        l="";
        c=null;
    }
    function m(n,t){
        window.$(l).prop("checked",false);
        window.$("#vehicle-"+n).prop("checked",true);
        l="#vehicle-"+n;
        c=t;
    }
    function k(){
        if(pendingAction){
            var act=pendingAction;
            pendingAction=null;
            if("buy"===act){
                if(!c){L("Please select a vehicle first.","warning");return;}
                if(!o){L("Please select a parking space first.","warning");return;}
                window.$.post("https://cm-parking-v2/confirmDialog",JSON.stringify({selectedVehicle:c,locationIndex:o,purchase:true}),function(res){
                    if(res&&(res.success||res.ok)){
                        v();
                        window.$(".wrapper").css("display","none");
                        window.$.post("https://cm-parking-v2/close",JSON.stringify({}));
                        if(res.message){L(res.message,res.type||"info");}
                    }else{
                        L((res&&res.message)||"Purchase failed.","error");
                    }
                });
                return;
            }
            if("buyBusiness"===act){
                window.$.post("https://cm-parking-v2/buyBusiness",JSON.stringify({}),function(res){
                    v();
                });
                return;
            }
            if("cancel"===act||"cancelAndBuy"===act){
                window.$.post("https://cm-parking-v2/cancel",JSON.stringify({locationIndex:o}),function(res){
                    if(res&&(res.success||res.ok)){
                        window.__alreadyParked=false;
                        window.__alreadyParkedName="";
                        for(let j=0;j<w.length;j++){
                            if(w[j].IsOwner){w[j].IsOwner=false;w[j].Free=true;}
                        }
                        window.$("#callCar").hide();
                        window.$("#cancel").hide();
                        if("cancelAndBuy"===act){
                            showVehiclePicker();
                            L("Previous parking cancelled. Select vehicle to buy this spot.","info");
                        }else{
                            v();
                            f();
                            L(res.message||"Parking cancelled and vehicle removed.","success");
                        }
                    }else{
                        L((res&&res.message)||"Request failed.","error");
                    }
                });
                return;
            }
            if("recall"===act){
                if(!o){L("Please select a parking space first.","warning");return;}
                window.$.post("https://cm-parking-v2/recallSpot",JSON.stringify({locationIndex:o}),function(res){
                    v();
                    L((res&&res.message)?res.message:"Vehicle recall requested.","info");
                });
                return;
            }
        }
        if(!c){
            L("Please select a vehicle first.","warning");
            return;
        }
        if(!o){
            L("Please select a parking space first.","warning");
            return;
        }
        if(buyMode){
            showConfirm("buy");
            return;
        }
        window.$.post("https://cm-parking-v2/confirmDialog",JSON.stringify({selectedVehicle:c,locationIndex:o,purchase:buyMode}),function(res){
            if(res&&(res.success||res.ok)){
                v();
                L(res.message||"Request completed.","success");
            }else{
                L((res&&res.message)||"Request failed.","error");
            }
        });
    }
    window.$(document).ready(function(){
        if(!window.$(".dialog-confirm-msg").length){
            window.$(".dialog-list").after('<div class="dialog-confirm-msg" style="display:none;font-size:18px;text-align:center;padding:25px;color:#c2d2dc;line-height:1.5;"></div>');
        }
        function toggleOwnerDashboard(show){
            if(show){
                window.$(".parking-content").hide();
                window.$(".parking-footer").hide();
                window.$(".dialog-box").hide();
                window.$("#ownerDashboard").css("display","flex");
            }else{
                window.$("#ownerDashboard").hide();
                window.$(".parking-content").show();
                window.$(".parking-footer").show();
            }
        }
        function renderBusinessUI(hData){
            if(!hData)return;
            window.$(".business-subinfo, .business-header-actions").remove();

            if(!window.$("#ownerDashboard").length){
                var dashHtml='<div id="ownerDashboard">'+
                    '<div class="owner-dash-top">'+
                        '<div>'+
                            '<h1 id="dashLotName">PARKING BUSINESS CONSOLE</h1>'+
                            '<span>Manage daily parking rental rates, review property stats, and withdraw vault balance.</span>'+
                        '</div>'+
                        '<button id="dashCloseBtn" class="btn-header-action" style="background:rgba(255,255,255,0.1);color:#ffffff;border:1px solid #213b4a;">CLOSE DASHBOARD</button>'+
                    '</div>'+
                    '<div class="owner-dash-grid">'+
                        '<div class="owner-dash-card">'+
                            '<div>'+
                                '<div class="owner-card-title">BUSINESS VAULT <span style="font-size:0.9vw;color:#2ecc71;">80% REVENUE CUT</span></div>'+
                                '<span style="font-size:0.9vw;color:#829dae;">Accumulated customer space rental funds</span>'+
                                '<div id="dashVaultAmount" class="owner-vault-amount">$0</div>'+
                                '<div class="owner-stat-row"><span>Today\'s Income</span><span id="dashDailyIncome" class="val green">$0</span></div>'+
                                '<div class="owner-stat-row"><span>Weekly Income</span><span id="dashWeeklyIncome" class="val yellow">$0</span></div>'+
                            '</div>'+
                            '<button id="dashWithdrawBtn" class="btn-header-action btn-buy-biz" style="width:100%;height:5.5vh;font-size:1.1vw;margin-top:2vh;">WITHDRAW VAULT FUNDS</button>'+
                        '</div>'+
                        '<div class="owner-dash-card">'+
                            '<div>'+
                                '<div class="owner-card-title">DAILY RENTAL RATE TIERS <span style="font-size:0.9vw;color:#00e5ff;">ACTIVE: <span id="dashCurrentTierLabel">NORMAL</span></span></div>'+
                                '<span style="font-size:0.9vw;color:#829dae;display:block;margin-bottom:1.2vh;">Select customer pricing rate per 24 hours:</span>'+
                                '<div class="owner-tier-btn" data-tier="low">'+
                                    '<div class="owner-tier-left"><h3>LOW TIER</h3><p>Budget-friendly discount to boost parking volume</p></div>'+
                                    '<div class="owner-tier-right"><div class="price">$1,000</div><span class="badge" style="display:none;">ACTIVE</span></div>'+
                                '</div>'+
                                '<div class="owner-tier-btn" data-tier="normal">'+
                                    '<div class="owner-tier-left"><h3>NORMAL TIER</h3><p>City-regulated standard competitive pricing</p></div>'+
                                    '<div class="owner-tier-right"><div class="price">$2,500</div><span class="badge" style="display:none;">ACTIVE</span></div>'+
                                '</div>'+
                                '<div class="owner-tier-btn" data-tier="high">'+
                                    '<div class="owner-tier-left"><h3>HIGH TIER</h3><p>Premium rate for high-demand downtown lots</p></div>'+
                                    '<div class="owner-tier-right"><div class="price">$5,000</div><span class="badge" style="display:none;">ACTIVE</span></div>'+
                                '</div>'+
                            '</div>'+
                            '<div style="font-size:0.85vw;color:#829dae;text-align:center;">Selecting a tier applies immediately to all new spot rentals.</div>'+
                        '</div>'+
                        '<div class="owner-dash-card">'+
                            '<div>'+
                                '<div class="owner-card-title">PROPERTY VALUATION</div>'+
                                '<div class="owner-stat-row"><span>State Valuation</span><span id="dashStateVal" class="val yellow">$250,000</span></div>'+
                                '<div class="owner-stat-row"><span>Total Capacity</span><span id="dashTotalCap" class="val">0 SPOTS</span></div>'+
                                '<div class="owner-stat-row"><span>Occupancy</span><span id="dashOccupancy" class="val green">0 / 0</span></div>'+
                                '<div class="owner-stat-row"><span>Registered Owner</span><span id="dashOwnerName" class="val" style="color:#00e5ff;">You</span></div>'+
                                '<div class="owner-stat-row"><span>Business Status</span><span class="val green">ACTIVE</span></div>'+
                            '</div>'+
                            '<button id="dashReturnSpotsBtn" class="btn-header-action" style="background:rgba(255,255,255,0.08);color:#ffffff;border:1px solid #213b4a;width:100%;height:5vh;font-size:1vw;margin-top:2vh;">VIEW PARKING LOT GRID</button>'+
                        '</div>'+
                    '</div>'+
                    '<div class="owner-dash-footer">'+
                        '<span style="color:#829dae;font-size:0.95vw;margin-right:auto;">CM Server Parking Management • Changes save automatically</span>'+
                    '</div>'+
                '</div>';
                window.$(".wrapper").append(dashHtml);

                window.$("#dashCloseBtn, #dashReturnSpotsBtn").click(function(){
                    toggleOwnerDashboard(false);
                });

                window.$("#dashWithdrawBtn").click(function(){
                    window.$.post("https://cm-parking-v2/withdrawRevenue",JSON.stringify({}));
                });

                window.$(".owner-tier-btn").click(function(){
                    var tier=window.$(this).data("tier");
                    if(tier){
                        window.$.post("https://cm-parking-v2/setPriceTier",JSON.stringify({tier:tier}));
                    }
                });
            }

            window.$("#dashLotName").text((hData.ParkingName||"PARKING").toUpperCase()+" MANAGEMENT CONSOLE");
            window.$("#dashVaultAmount").text("$"+(Number(hData.BusinessBalance)||0).toLocaleString());
            window.$("#dashDailyIncome").text("$"+(Number(hData.DailyIncome)||0).toLocaleString());
            window.$("#dashWeeklyIncome").text("$"+(Number(hData.WeeklyIncome)||0).toLocaleString());
            window.$("#dashStateVal").text("$"+(Number(hData.StateValue)||250000).toLocaleString());

            var tot=Number(hData.TotalSpaces)||(w?w.length:12);
            var occ=Number(hData.OccupiedSpots)||Math.max(0,tot-(Number(hData.FreeSpaces)||0));
            var pct=Math.round((occ/tot)*100);
            window.$("#dashTotalCap").text(tot+" SPOTS");
            window.$("#dashOccupancy").text(occ+" / "+tot+" ("+pct+"%)");
            window.$("#dashOwnerName").text(hData.OwnerName||"You");

            var activeTier=(hData.PriceTier||"normal").toLowerCase();
            window.$("#dashCurrentTierLabel").text(activeTier.toUpperCase());
            window.$(".owner-tier-btn").removeClass("active");
            window.$(".owner-tier-btn .badge").hide();
            var activeBtn=window.$('.owner-tier-btn[data-tier="'+activeTier+'"]');
            activeBtn.addClass("active");
            activeBtn.find(".badge").show();

            if(hData.InitialTab==="owner"&&hData.IsOwner){
                toggleOwnerDashboard(true);
            }else{
                toggleOwnerDashboard(false);
            }
        }
        window.addEventListener("message",function(n){
            switch(n.data.type){
                case"showMenu":
                    window.__alreadyParked=!!n.data.headerData.AlreadyParked;
                    window.__alreadyParkedName=n.data.headerData.AlreadyParkedName||"";
                    window.__headerData=n.data.headerData;
                    e(2,s=n.data.headerData.ParkingName);
                    e(3,a=n.data.headerData.PricePerSpot);
                    e(4,d=n.data.headerData.FreeSpaces);
                    e(5,r=n.data.headerData.Balance);
                    window.$(".wrapper").css("display","flex");
                    e(0,w=n.data.parkingSpots);
                    e(6,u=n.data.ownedVehicles);
                    f();
                    renderBusinessUI(n.data.headerData);
                    if(w.some(function(n){return n.IsOwner;})){
                        o=w.find(function(n){return n.IsOwner;}).CoordsIdx;
                        window.$("#callCar").show();
                        window.$("#cancel").show();
                    }else{
                        window.$("#callCar").hide();
                        if(window.__alreadyParked){
                            window.$("#cancel").show();
                        }else{
                            window.$("#cancel").hide();
                        }
                    }
                    if(n.data.headerData.SelectedSpot || (w.length === 1 && w[0].Free)){
                        var targetSpot = n.data.headerData.SelectedSpot || w[0].CoordsIdx;
                        o = String(targetSpot);
                        var el = window.$("#spot-" + o);
                        if(el.length){
                            i = el.html();
                            el.empty().append('<span class="spot-tag" style="position:absolute;top:10px;font-size:0.95vw;color:#00e5ff;font-weight:800;letter-spacing:0.05vw;">SPOT #'+o+'</span><h1 style="color:#00e5ff;font-weight:800;">Selected</h1>');
                            el.addClass("selected");
                        }
                        window.$("#buySpot").show();
                    }
                    break;
                case"closeMenu":
                    window.$(".wrapper").css("display","none");
                    window.__alreadyParked=false;
                    toggleOwnerDashboard(false);
                    v();
                    break;
                case"updateSpots":
                    e(0,w=n.data.parkingSpots);
                    f();
                    break;
            }
        });
        window.$(document).keyup(function(n){
            if(27==n.keyCode){
                window.$(".wrapper").css("display","none");
                toggleOwnerDashboard(false);
                window.$.post("https://cm-parking-v2/close",JSON.stringify({}));
            }
        });
        window.$("#buySpot").click(function(){
            if(!o){
                L("Please select a parking space first.","warning");
                return;
            }
            if(window.__alreadyParked){
                showConfirm("cancelAndBuy");
            }else{
                showVehiclePicker();
            }
        });
        window.$("#cancel").click(function(){
            showConfirm("cancel");
        });
        window.$("#callCar").click(function(){
            showConfirm("recall");
        });
    });
    return[w,p,s,a,d,r,u,g,v,m,k,(n,t)=>m(n,t),()=>k(),()=>v(),()=>g(0),()=>g(1)];
}return new class extends class{$destroy(){!function(n,t){const e=n.$$;null!==e.fragment&&(i(e.on_destroy),e.fragment&&e.fragment.d(t),e.on_destroy=e.fragment=null,e.ctx=[])}(this,1),this.$destroy=n}$on(n,t){const e=this.$$.callbacks[n]||(this.$$.callbacks[n]=[]);return e.push(t),()=>{const n=e.indexOf(t);-1!==n&&e.splice(n,1)}}$set(n){var t;this.$$set&&(t=n,0!==Object.keys(t).length)&&(this.$$.skip_bound=!0,this.$$set(n),this.$$.skip_bound=!1)}}{constructor(n){super(),A(this,n,F,E,s,{})}}({target:document.body})}();
//# sourceMappingURL=bundle.js.map
