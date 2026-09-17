let scriptName = 'id-electrician'
let employed = false

window.addEventListener('message', function(event) {
    let item = event.data;
    if (item.type === "show") {
        if (item.status == true) {
            $('#requirements').html("");
            $("#main").fadeIn();
        } else {
            $('#requirements').html("");
            $("#main").fadeOut("fast");
        }
    } else if (item.type === "addrequirements") {
        $('#requirements').append (`
            <div class="item">
                <span>${item.data}</span>
            </div>
        `);
    } else if (item.type === "showfixedpanels") {
        if (item.status == true) {
            $('#panelsfixed').fadeIn();
        } else {
            $('#panelsfixed').fadeOut("fast");
        }
    }
    $(`#button`).click(function(){
        $.post('https://' + scriptName + '/startjob');
    })
});

function button() {
    employed = !employed
    if (!employed) {
        buttontext.innerHTML = 'GET EMPLOYED'
    } else {
        buttontext.innerHTML = 'LEAVE'
    };
    
    $.post('https://' + scriptName + '/startjob', JSON.stringify({}));
}

$(function(){
    $('#main').hide()
    $('#panelsfixed').hide()
    $('.wrapper').append (`
        <button onclick="button()" id="buttontext">GET EMPLOYED</button>
    `);

    window.addEventListener('message', function (event) {
        try {
            switch(event.data.action) {
                case 'jobdescription':
                    if (event.data.value != null) jobdescription.innerHTML = event.data.value;
                break;

                case 'professionlevel':
                    if (event.data.value != null) professionlevel.innerHTML = event.data.value;
                break;

                case 'button':
                    if (event.data.value != null) buttontext.innerHTML = event.data.value;
                break;

                case 'priceperpanel':
                    if (event.data.value != null) priceperpanel.innerHTML = '$' + event.data.value;
                break;

                case 'depositplateprice':
                    if (event.data.value != null) depositplateprice.innerHTML = '$' + event.data.value;
                break;

                case 'panelsrepaired':
                    if (event.data.value != null) panelsrepaired.innerHTML = event.data.value;
                break;
            }
    } catch(err) {}
    });
    
    $(document).keyup(function(e) {
        if (e.key === "Escape") { 
            $("#main").fadeOut("fast");
            $.post('https://' + scriptName + '/close', JSON.stringify({
                type: 'close',
            }));
        }
    });
})
