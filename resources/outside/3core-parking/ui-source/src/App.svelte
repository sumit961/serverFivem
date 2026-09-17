<script>
	let parkingSpots = [];
	let currentPage = 1;
	let parkingPages = [];
	let currentText;
	let selectedLocation;
	let parkingName;
	let pricePerSpot;
	let freeSpaces;
	let balance;
	let checkedElement;
	let selectedVehicle;
	let ownedVehicles = [];
	function createParkingPage() {
		window.$('#list-1').empty();
		window.$('#list-2').empty();
		window.$('#buySpot').hide();
		window.$('#callCar').hide();
		window.$('#cancel').hide();
		currentPage = 1;
		let currentIdx = 0;
		let pagePush = 1;
		parkingPages[1] = [];
		for (let idx = 0; idx < parkingSpots.length; idx++) {
			if (currentIdx < 10) {
				parkingPages[pagePush].push(parkingSpots[idx]);
				currentIdx++;
			} else {
				currentIdx = 0;
				pagePush++;
				parkingPages[pagePush] = [];
			}
		}
		let currentRow = 1;
		if (parkingPages[1].length > 5) {
			window.$('#list-1').show();
			window.$('#list-2').show();
		} else {
			window.$('#list-1').show();
			window.$('#list-2').hide();
		}
		for (let idx = 0; idx < parkingPages[1].length; idx++) {
			if (idx == 5) currentRow = 2;
			if (currentRow == 1) {
				if (parkingPages[1][idx]['Free']) {
					window.$('#list-1').append('<div class="parking-main-content-item" owned="false" location='+parkingPages[1][idx]['CoordsIdx']+' id="spot-'+parkingPages[1][idx]['CoordsIdx']+'"><h1>Available<span>'+pricePerSpot+'$</span></h1></div>');
				} else {
					if (parkingPages[1][idx]['IsOwner']) {
						window.$('#list-1').append('<div class="parking-main-content-item" owned="true" location='+parkingPages[1][idx]['CoordsIdx']+' id="spot-'+parkingPages[1][idx]['CoordsIdx']+'"><h1>Your Parking<span>Owned</span></h1></div>');
					} else {
						window.$('#list-1').append('<div class="parking-main-content-item owned" owned="false"><h1>Not Available<span>Owned</span></h1></div>');
					}
				}
			} else if (currentRow == 2) {
				if (parkingPages[1][idx]['Free']) {
					window.$('#list-2').append('<div class="parking-main-content-item" owned="false" location='+parkingPages[1][idx]['CoordsIdx']+' id="spot-'+parkingPages[1][idx]['CoordsIdx']+'"><h1>Available<span>'+pricePerSpot+'$</span></h1></div>');
				} else {
					if (parkingPages[1][idx]['IsOwner']) {
						window.$('#list-2').append('<div class="parking-main-content-item" owned="true" location='+parkingPages[1][idx]['CoordsIdx']+' id="spot-'+parkingPages[1][idx]['CoordsIdx']+'"><h1>Your Parking<span>Owned</span></h1></div>');
					} else {
						window.$('#list-2').append('<div class="parking-main-content-item owned" owned="false"><h1>Not Available<span>Owned</span></h1></div>');
					}
				}
			}
			window.$('#spot-'+parkingPages[1][idx]['CoordsIdx']+'').click(function() {
				selectedLocation = window.$(this).attr('location');
				window.$('.selected').empty().append(currentText);
				currentText = window.$(this).html();
				if (window.$(this).attr('owned') == 'false') {
					window.$(this).empty();
					window.$(this).append('<h1>Selected</h1>');
					window.$('#callCar').hide();
					window.$('#cancel').hide();
					window.$('#buySpot').show();
				} else {
					window.$('#buySpot').hide();
					window.$('#callCar').show();
					window.$('#cancel').show();
				}
				window.$('.selected').removeClass('selected');
				window.$(this).addClass('selected');
			});
		}
	}
	function showPage(pageIdx) {
		if (parkingPages[pageIdx]) {
			window.$('#list-1').empty();
			window.$('#list-2').empty();
			window.$('#buySpot').hide();
			window.$('#callCar').hide();
			window.$('#cancel').hide();
			if (parkingPages[pageIdx].length > 5) {
				window.$('#list-1').show();
				window.$('#list-2').show();
			} else {
				window.$('#list-1').show();
				window.$('#list-2').hide();
			}
			let currentRow = 1;
			for (let idx = 0; idx < parkingPages[pageIdx].length; idx++) {
				if (idx == 5) currentRow = 2;
				if (currentRow == 1) {
					if (parkingPages[pageIdx][idx]['Free']) {
						window.$('#list-1').append('<div class="parking-main-content-item" owned="false" location='+parkingPages[pageIdx][idx]['CoordsIdx']+' id="spot-'+parkingPages[pageIdx][idx]['CoordsIdx']+'"><h1>Available<span>'+pricePerSpot+'$</span></h1></div>');
					} else {
						if (parkingPages[pageIdx][idx]['IsOwner']) {
							window.$('#list-1').append('<div class="parking-main-content-item" owned="true" location='+parkingPages[pageIdx][idx]['CoordsIdx']+' id="spot-'+parkingPages[pageIdx][idx]['CoordsIdx']+'"><h1>Your Parking<span>Owned</span></h1></div>');
						} else {
							window.$('#list-1').append('<div class="parking-main-content-item owned" owned="false"><h1>Not Available<span>Owned</span></h1></div>');
						}
					}
				} else if (currentRow == 2) {
					if (parkingPages[pageIdx][idx]['Free']) {
						window.$('#list-2').append('<div class="parking-main-content-item" owned="false" location='+parkingPages[pageIdx][idx]['CoordsIdx']+' id="spot-'+parkingPages[pageIdx][idx]['CoordsIdx']+'"><h1>Available<span>'+pricePerSpot+'$</span></h1></div>');
					} else {
						if (parkingPages[pageIdx][idx]['IsOwner']) {
							window.$('#list-2').append('<div class="parking-main-content-item" owned="true" location='+parkingPages[pageIdx][idx]['CoordsIdx']+' id="spot-'+parkingPages[pageIdx][idx]['CoordsIdx']+'"><h1>Your Parking<span>Owned</span></h1></div>');
						} else {
							window.$('#list-2').append('<div class="parking-main-content-item owned" owned="false"><h1>Not Available<span>Owned</span></h1></div>');
						}
					}
				}
				window.$('#spot-'+parkingPages[pageIdx][idx]['CoordsIdx']+'').click(function() {
					selectedLocation = window.$(this).attr('location');
					window.$('.selected').empty().append(currentText);
					currentText = window.$(this).html();
					if (window.$(this).attr('owned') == 'false') {
						console.log('1');
						window.$(this).empty();
						window.$(this).append('<h1>Selected</h1>');
						window.$('#callCar').hide();
						window.$('#cancel').hide();
						window.$('#buySpot').show();
					} else {
						console.log('2');
						window.$('#buySpot').hide();
						window.$('#callCar').show();
						window.$('#cancel').show();
					}
					window.$('.selected').removeClass('selected');
					window.$(this).addClass('selected');
				});
			}
		}
	}
	function listItem(list) {
		if (list == 0) {
			if (parkingPages[currentPage - 1]) {
				currentPage--;
				showPage(currentPage);
			} else {
				return;
			}
		} else if (list == 1) {
			if (parkingPages[currentPage + 1]) {
				currentPage++;
				showPage(currentPage);
			} else {
				return;
			}
		}
    }
	window.$(document).ready(function() {
		window.addEventListener('message', event => {
			let type = event.data.type;
			switch (type) {
				case 'showMenu':
					parkingName = event.data.headerData['ParkingName'];
					pricePerSpot = event.data.headerData['PricePerSpot'];
					freeSpaces = event.data.headerData['FreeSpaces'];
					balance = event.data.headerData['Balance'];
					window.$('.wrapper').css('display', 'flex');
					parkingSpots = event.data.parkingSpots;
					ownedVehicles = event.data.ownedVehicles;
					createParkingPage();
					break;
				case 'updateSpots':
					parkingSpots = event.data.parkingSpots;
					createParkingPage();
					break;
			}
		});
		window.$(document).keyup(function(e) {
			if (e.keyCode == 27) {
				window.$('.wrapper').css('display', 'none');
				window.$.post('https://3core-parking/close', JSON.stringify({}));
			}
		});
		window.$('#buySpot').click(function() {
			window.$.post('https://3core-parking/buySpot', JSON.stringify({
				['locationIndex']: selectedLocation
			}));
		});
		window.$('#cancel').click(function() {
			window.$.post('https://3core-parking/cancel', JSON.stringify({
				['locationIndex']: selectedLocation
			}));
		});
		window.$('#callCar').click(function() {
			window.$('#buySpot').hide();
			window.$('#callCar').hide();
			window.$('#cancel').hide();
			window.$('.parking-content-arrow-left').hide();
			window.$('.parking-content-arrow-right').hide();
			window.$('.parking-main-content-list').hide();
			window.$('.dialog-box').show();
		});
	});
	function closeDialog() {
		window.$('.dialog-box').hide();
		window.$('.parking-content-arrow-left').show();
		window.$('.parking-content-arrow-right').show();
		window.$('.parking-main-content-list').show();
		showPage(currentPage);
		window.$(checkedElement).prop('checked', false);
		checkedElement = '';
		selectedVehicle = null;
	}
	function check(index, vehicle) {
		window.$(checkedElement).prop('checked', false);
		window.$('#vehicle-'+index+'').prop('checked', true);
		checkedElement = '#vehicle-'+index+'';
		selectedVehicle = vehicle;
	}
	function confirmDialog() {
		if (selectedVehicle) {
			window.$.post('https://3core-parking/confirmDialog', JSON.stringify({
				['selectedVehicle']: selectedVehicle,
				['locationIndex']: selectedLocation
			}), function(data) {
				if (data['success']) {
					closeDialog();
					notify(data['message']);
				} else {
					notify(data['message']);
				}
			});
		}
	}
	function notify(message) {
		window.$('.notification').css('display', 'flex');
		window.$('.notification').empty();
		window.$('.notification').append('<h1>'+message+'</h1>');
		setTimeout(function() {window.$('.notification').hide()}, 3000);
	}
</script>

<main>
	<div class="wrapper">
		<i class="parking-bg-image"></i>
		<div class="parking-header">
			<h1>{parkingName}<span>Parking is given for 24 hours</span></h1>
			<div class="parking-header-right">
				<h1>Free spaces<span>{freeSpaces}</span></h1>
				<h1>Cost per space<span>{pricePerSpot}$</span></h1>
				<h1>Balance<span>{balance}$</span></h1>
			</div>
		</div>
		<div class="parking-content">
			<div class="dialog-box">
				<p class="dialog-box-header">Select Vehicle</p>
				<div class="dialog-list">
					{#each ownedVehicles as vehicle, index}
						<div class="dialog-list-item">
							<input on:click={() => check(index, vehicle)} class="dialog-checked" id="vehicle-{index}" type="radio">
							<label for="vehicle-{index}"><p>{vehicle['Label']}</p></label>
						</div>
					{/each}
				</div>
				<div class="dialog-buttons">
					<button on:click={() => confirmDialog()} class="b-yellow">Confirm</button>
					<button on:click={() => closeDialog()} class="b-white">Cancel</button>
				</div>
			</div>
			<div class="parking-content-arrow-left" on:click={() => listItem(0)}></div>
			<div class="parking-main-content-list">
				<div id="list-1" class="parking-main-content-line"></div>
				<div id="list-2" class="parking-main-content-line"></div>
				<div class="pages">
					<span>{currentPage} / {Math.round(parkingSpots.length / 10)}</span>
				</div>
			</div>
			<div class="parking-content-arrow-right" on:click={() => listItem(1)}></div>
		</div>
		<div class="parking-footer">
			<div class="parking-footer-left">
			</div>
			<div class="parking-footer-right">
				<button id="callCar" class="b-blue">Call Your Car</button>
				<button id="cancel" class="b-cancel">Cancel Parking</button>
				<button id="buySpot" class="b-blue">Buy Location</button>
			</div>
		</div>
		<div class="notification"></div>
	</div>
</main>

<style>
	@import url('http://fonts.cdnfonts.com/css/akrobat');
	* {
		font-family: 'Akrobat Black', sans-serif;
		transition: transform .23232323s ease-in-out;
		-webkit-transition: transform .23232323s ease-in-out;
		-moz-transition: transform .23232323s ease-in-out;
		user-select: none;
		margin: 0;
		padding: 0;
		outline: none;
	}
	.wrapper {
		position: fixed;
		display: none;
		width: 100%;
		height: 100%;
		top: 0;
		left: 0;
	}
	.parking-bg-image {
		position: absolute;
		top: 0;
		left: 0;
		width: 100%;
		height: 100%;
		pointer-events: none;
		background: url('https://cdn.discordapp.com/attachments/1008791639646548078/1013480706082619532/dnasjdhklbnsadkblhjsbhkdlashjbdbjas.png') no-repeat;
		background-size: 100% 100%;
	}
	.parking-header {
		position: absolute;
		display: flex;
		width: 100%;
		justify-content: space-around;
		align-items: center;
		margin-top: 6vh;
	}
	.parking-header h1 {
		display: flex;
		flex-direction: column;
		font-size: 3vw;
		text-transform: uppercase;
		color: white;
	}
	.parking-header h1 > span {
		display: flex;
		align-items: center;
		font-size: 2vw;
		color: hsla(0, 0%, 100%, .4);
		letter-spacing: 0.2vw;
		margin-top: 1vh;
	}
	.parking-header > h1 > span::before {
		background: url('https://cdn.discordapp.com/attachments/928768829675429938/1013134364479070358/unknown.png') no-repeat;
		background-size: 100% 100%;
		content: "";
		width: 1.5vw;
		height: 2.7vh;
		margin-right: 1vw
	}
	.parking-header-right {
		display: flex;
		align-items: center;
	}
	.parking-header-right > h1 {
		padding-right: 1.6vw;
		padding-left: 1.6vw;
		font-size: 2vw;
		color: hsla(0, 0%, 100%, .4);
		text-transform: uppercase;
		border-right: 0.2vw solid hsla(0, 0%, 100%, .4);
		text-align: right
	}
	.parking-header-right > h1 > span {
		display: block;
		color: white;
		font-size: 1.5vw;
		text-align: right;
		margin-top: 1vh
	}
	.parking-content {
		position: absolute;
		width: 100%;
		display: flex;
		justify-content: center;
		align-items: center;
		align-self: center;
	}
	.parking-content-arrow-left {
		width: 4vw;
		height: 7.4vh;
		border-radius: 0.3vw;
		background: hsla(0, 0%, 100%, .1);
		display: flex;
		justify-content: center;
		align-items: center;
		margin-right: 3vw;
	}
	.parking-content-arrow-right {
		width: 4vw;
		height: 7.4vh;
		border-radius: 0.3vw;
		background: hsla(0, 0%, 100%, .1);
		display: flex;
		justify-content: center;
		align-items: center;
		margin-left: 3vw;
	}
	.parking-content-arrow-left:before {
		content: "";
		background: url('https://cdn.discordapp.com/attachments/928768829675429938/1013136432182853743/unknown.png') no-repeat;
		background-size: 100% 100%;
		width: 2.5vw;
		height: 4.4vh
	}
	.parking-content-arrow-left:hover {
		background: #1e88e5;
	}
	.parking-content-arrow-right:before {
		transform: rotate(180deg);
		content: "";
		background: url('https://cdn.discordapp.com/attachments/928768829675429938/1013136432182853743/unknown.png') no-repeat;
		background-size: 100% 100%;
		width: 2.5vw;
		height: 4.4vh
	}
	.parking-content-arrow-right:hover {
		background: #1e88e5;
	}
	.parking-main-content-list {
		border-left: 0.3vw solid hsla(0, 0%, 100%, .4);
		border-right: 0.3vw solid hsla(0, 0%, 100%, .4);
		border-top: 0.3vw solid hsla(0, 0%, 100%, .4);
		position: relative;
		display: flex;
		flex-direction: column;
		align-items: center
	}
	.parking-main-content-line {
		border-bottom: 0.3vw solid hsla(0, 0%, 100%, .4);
		display: flex
	}
	:global(.parking-main-content-item) {
		width: 8.5vw;
		height: 22vh;
		border-right: 0.3vw solid hsla(0, 0%, 100%, .4);
		position: relative;
		display: flex;
		justify-content: center;
		align-items: center;
	}
	:global(.parking-main-content-item:last-child) {
		border: 0
	}
	:global(.parking-main-content-item > h1) {
		text-align: center;
		text-transform: uppercase;
		color: hsla(0, 0%, 100%, .4);
		letter-spacing: 0.05vw;
		font-size: 1vw;
	}
	:global(.parking-main-content-item > h1 > span) {
		display: block;
		font-size: 1.2vw;
		margin-top: 1vh;
		letter-spacing: 0;
	}
	:global(.parking-main-content-item:before) {
		content: "";
		position: absolute;
		width: 100%;
		height: 100%;
		background: hsla(0, 0%, 100%, .1);
		opacity: 0;
		pointer-events: none;
		border-radius: 0.3vw;
	}
	:global(.parking-main-content-item.selected) {
		background: hsla(0, 0%, 100%, .1);
		pointer-events: none;
	}
	:global(.parking-main-content-item:hover:before) {
		opacity: 1;
	}
	:global(.pages) {
		position: absolute;
		bottom: -4vh;
		color: hsla(0, 0%, 100%, .4);
		font-size: 1vw;
		letter-spacing: 0.2vw;
	}
	.parking-footer {
		position: absolute;
		width: 100%;
		display: flex;
		justify-content: space-between;
		align-items: center;
		bottom: 0;
		right: 0;
	}
	.parking-footer button {
		padding-left: 27px;
		padding-right: 27px;
		height: 80px;
		text-transform: uppercase;
		color: #fff;
		display: flex;
		justify-content: center;
		align-items: center;
		font-size: 24px;
		font-weight: 800;
		border-radius: 8px;
		border: 0;
	}
	.parking-footer button.b-blue {
		background: #1e88e5;
		color: white
	}
	.parking-footer button.b-up {
		background: hsla(0, 0%, 100%, .1);
	}
	.parking-footer button.b-cancel {
		background: #f44336;
	}
	.parking-footer button:hover {
		opacity: 0.8
	}
	.parking-footer-right {
		display: flex;
		align-items: center;
		gap: 1vw;
		margin: 2vw;
	}
	.parking-footer-left {
		margin: 2vw;
	}
	:global(.owned) {
		pointer-events: none;
	}
	#buySpot, #callCar, #cancel {
		display: none;
	}
	.dialog-box {
		position: absolute;
		align-self: center;
		background-size: 100% 100%;
		width: 35vw;
		height: fit-content;
		display: none;
		flex-direction: column;
		align-items: center;
		color: white;
	}
	.dialog-box-header {
		text-align: center;
		font-size: 2.5vw;
		text-transform: uppercase
	}
	.dialog-buttons {
		display: flex;
		align-items: center;
		justify-content: center;
	}
	.dialog-buttons > button {
		font-family: 'Akrobat Black', sans-serif;
		width: 10vw;
		height: 7vh;
		border: none;
		display: flex;
		justify-content: center;
		align-items: center;
		text-align: center;
		border-radius: 0.3vw;
		color: white;
		text-transform: uppercase;
		font-size: 1.5vw;
		margin-right: 2vw;
		transition: transform .23232323s ease-in-out;
		-webkit-transition: transform .23232323s ease-in-out;
		-moz-transition: transform .23232323s ease-in-out;
		cursor: pointer;
	}
	.dialog-buttons > button:last-child {
		margin-right: 0
	}
	.dialog-buttons > button.b-yellow {
		background: #1e88e5;
		color: white
	}
	.dialog-buttons > button.b-white {
		background: hsla(0, 0%, 100%, 0.1);
		color: white
	}
	.dialog-buttons > button:hover {
		transform: scale(1.1);
	}
	.dialog-list {
		max-height: 24vh;
		overflow: auto;
		margin-top: 2vh;
		margin-bottom: 2vh;
	}
	.dialog-list .dialog-list-item {
		margin-bottom: 0.7vh;
		display: flex;
		justify-content: center;
	}
	.dialog-list .dialog-list-item:last-child {
		margin-bottom: 0;
	}
	.dialog-list .dialog-list-item > input {
		display: none;
		opacity: 0;
		text-indent: -3000em;
		position: absolute;
	}
	.dialog-list .dialog-list-item > label > p {
		background: hsla(0, 0%, 100%, .1);
		border-radius: 0.2vw;
		position: relative;
		width: 18.3vw;
		height: 7.4vh;
		display: flex;
		justify-content: center;
		align-items: center;
		text-align: center;
		font-size: 1.5vw;
		color: white;
		padding-left: 0.5vw;
		padding-right: 0.5vw;
		transition: all .23232323s ease-in-out;
		-webkit-transition: all .23232323s ease-in-out;
		-moz-transition: all .23232323s ease-in-out;
		cursor: pointer;
	}
	.dialog-list .dialog-list-item .dialog-checked:checked + label > p {
		background: #1e88e5;
	}
	::-webkit-scrollbar {
		display: none;
	}
	.notification {
		position: absolute;
		display: none;
		justify-content: center;
		bottom: 4vh;
		left: 1vw;
        background-color: hsla(0, 0%, 100%, 0.1);
        padding: 1vw;
		border-radius: 1vw;
		font-size: 0.5vw;
		color: white;
	}
</style>