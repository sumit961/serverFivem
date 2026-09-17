/* cm-ui persistent overlay controller. This page stays loaded for the whole
   session (ui_page in fxmanifest.lua) so any resource can call the shared
   cm-interact / cm-dialogue components via exports without shipping its own
   copy of this markup. See client/interact.lua and client/dialogue.lua. */
(function () {
    'use strict';

    window.addEventListener('message', function (event) {
        var data = event.data || {};

        if (data.action === 'cmInteract:show') {
            CMUI.showInteract(data);
        } else if (data.action === 'cmInteract:hide') {
            CMUI.hideInteract();
        } else if (data.action === 'cmDialogue:open') {
            CMUI.openDialogue(data);
        } else if (data.action === 'cmDialogue:response') {
            CMUI.dialogueResponse(data);
        } else if (data.action === 'cmDialogue:restoreChoices') {
            CMUI.dialogueRestoreChoices(data);
        } else if (data.action === 'cmDialogue:close') {
            CMUI.closeDialogue();
        }
    });
})();
