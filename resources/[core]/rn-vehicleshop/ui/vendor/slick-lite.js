/* Minimal local Slick compatibility shim for FiveM NUI.
   The old CDN Slick dependency could fail to load and break the whole UI.
   This shim supports the methods used by this resource: init, refresh and slickRemove. */
(function(window){
  if(!window.jQuery) return;
  var $ = window.jQuery;
  if($.fn.slick) return;
  $.fn.slick = function(action){
    if(typeof action === 'string'){
      if(action === 'slickRemove'){
        return this.each(function(){ $(this).children().remove(); });
      }
      if(action === 'refresh' || action === 'setPosition' || action === 'unslick'){
        return this;
      }
      return this;
    }
    return this.each(function(){ $(this).addClass('slick-lite slick-initialized'); });
  };
})(window);
