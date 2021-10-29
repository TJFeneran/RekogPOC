var api_url = "https://no73r73wxl.execute-api.us-east-1.amazonaws.com/Production";
var s3sourcebucket = "rekog-src-ptcvcrevurmetdtx";
var ui_url = "http://rekog-ui-ptcvcrevurmetdtx.s3-website-us-east-1.amazonaws.com/";
var region = "us-east-1";

//var api_url = "${api_url}";
//var s3sourcebucket = "${s3sourcebucket}";
//var ui_url = "${ui_url}";
//var region = "${region}";

// Creates a new file and add it to our list
function ui_multi_add_file(id, file) {
	var template = $('#files-template').text();
	template = template.replace('%%filename%%', file.name);

	template = $(template);
	template.prop('id', 'uploaderFile' + id);
	template.data('file-id', id);

	$('#files').find('li.empty').fadeOut(); // remove the 'no files yet'
	$('#files').prepend(template);
}

// Changes the status messages on our list
function ui_multi_update_file_status(id, status, message) {
	$('#uploaderFile' + id).find('span').html(message).prop('class', 'status text-' + status);
}

// Updates a file progress, depending on the parameters it may animate it or change the color.
function ui_multi_update_file_progress(id, percent, color, active) {
	color = (typeof color === 'undefined' ? false : color);
	active = (typeof active === 'undefined' ? true : active);

	var bar = $('#uploaderFile' + id).find('div.progress-bar');

	bar.width(percent + '%').attr('aria-valuenow', percent);
	bar.toggleClass('progress-bar-striped progress-bar-animated', active);

	if(percent === 0) {
		bar.html('');
	} else {
		bar.html(percent + '%');
	}

	if(color !== false) {
		bar.removeClass('bg-success bg-info bg-warning bg-danger');
		bar.addClass('bg-' + color);
	}
}

// hides face holder container, shows empty collection notification
function showEmptyCollection() {
	$('#face-holder').hide();
	$('#empty-collection').fadeIn("");
}

// retrieves list of faces in custom collection and builds UI
function listFaces() {
	
	$('#face-holder').html("");
	$('#empty-collection').hide();
	$('#loader').show();
	
	// call listfaces API
	$.get(api_url + "/index/listfaces", function(data) {
		if(data.length > 0) {
			
			var indexcount = 1;
			
			// iterate through response objects
			for(var key in data) {
				
				// build person's card HTML
				var updatestr = "\
				<div class='col-lg-3 col-md-3 py-1' id='face_"+data[key].faceid.S+"'>\
					<div class='card mb-3 shadow-sm'>\
						<div class='bd-placeholder-img card-img-top' width='100%' height='225'>\
							<img src='"+data[key].imageURL.S+"' name='"+data[key].s3key.S+"' id='img_"+data[key].faceid.S+"' />\
						</div>\
						<div class='card-body'>\
							<div class='form-group'>\
								<input type='text' tabindex='"+indexcount+"' data-orig='"+data[key].personName+"' name='"+data[key].faceid.S+"' id='name_"+data[key].faceid.S+"' class-'form-control' placeholder='Enter name...' value='' />\
							</div>\
							<div class='d-flex justify-content-between align-items-center'>\
								<div class='btn-group'>\
									<button type='button' name='"+data[key].faceid.S+"' class='button-delete btn btn-sm btn-outline-secondary'>Delete</button>\
								</div>\
								<small class='text-muted'><a href='"+data[key].imageURL.S+"' target='_blank' style='color:#777;'><i class='fas fa-external-link-alt'></i></a></small>\
							</div>\
						</div>\
						<div class='statusbar status-bad' id='status_"+data[key].faceid.S+"'></div>\
					</div>\
				</div>";
				
				// append person's card to UI
				$('#face-holder').append(updatestr).show();
				
				var personname = typeof(data[key].personName) == "undefined" ? "" : data[key].personName;
				
				if(personname.length > 0) {
					
					// update name after appending card (to account for apostrophes in a person's name)
					$("#name_"+data[key].faceid.S).val(personname);
					
					// change status bar color
					$("#status_"+data[key].faceid.S).removeClass("status-bad").removeClass("status-active").addClass("status-good");
				}
				
				// increment tabindex input field attribute (for smoother tabbing through input fields)
				++indexcount;
			}
			
			$('#loader').hide();
		} else {
			//show empty collection message
			$('#loader').hide();
			$('#empty-collection').fadeIn("fast");
		}
	});
	
}

// On DOM ready
$(document).ready(function(){
	
	// Top Header refresh icon
	$(document).on("click","i.top-refresh",function(event){
		listFaces();
	});
	
	// Top Header info panel
	$(document).on("click","i.top-info",function(event) {
		$('#info-apiurl').text(api_url);
		$('#info-s3sourcebucket').text(s3sourcebucket);
		$('#info-region').text(region);
		$('#info-uiurl').html("<a href='http://"+ui_url+"'>http://"+ui_url+"</a>");
		$('#info-details').slideToggle();
	});
	
	// Top Header Test panel
	$(document).on("click","i.top-test",function(event) {
		$('#test-container').slideToggle();
	});
	
	// Top Header Upload panel
	$(document).on("click","i.top-upload",function(event) {
		$('#uploader-container').slideToggle();
	});
	
	// Top Header DeleteCollection panel
	$(document).on("click","i.top-deletecollection",function(event) {
		$('#info-deletecollection').slideToggle();
	});
	
	// Empty Collection refresh link
	$(document).on("click","#empty_refresh",function(event){
		listFaces();
		event.preventDefault();
	});
	
	// RESET COLLECTIONS
	$(document).on("click","#delete-collection",function(event){
		$(this).prop("disabled",true);
		$('#face-holder').html("");
		$('#empty-collection').hide();
		$('#loader').show();
		
		$.post(api_url + "/index/deletecollections", function(data) {
			$('#delete-collection').prop("disabled",false);
			listFaces();		
		});
		
		
		event.preventDefault();
	});
	
	// DELETE person (removes from DynamoDB and removes from Custom Face Collection)
	$(document).on("click",".card .button-delete",function(event) {
		var faceid = $(this).attr("name");
		
		if(faceid.length > 0) {

			// change status bar color
			$("#status_"+faceid).removeClass("status-bad").removeClass("status-good").addClass("status-active");
			
			// call delete face API, then remove face from UI. Show empty collection if no faces left.
			$.post(api_url + "/index/deletefaces?faceid="+faceid+"&s3key="+$('#img_'+faceid).attr("name"), function(data) {
				$('#face_'+faceid).fadeOut("normal",function(){
					$(this).remove();
					
					if(!($('#face-holder div').length > 0)) {
						showEmptyCollection();
					}
				});
											
			});
		}
	});
	
	// ENTER press on name input field
	$(document).on("keypress",".card input",function(event) {
		var code = event.keyCode || event.which;
		if(code == 13) {
			$(this).trigger("blur");
		}
	});
	
	// UPDATE name on blur or enter press trigger
	$(document).on("blur",".card input",function(event){
		
		var faceid = $(this).attr("name");
		var updatename = $(this).val();
		
		// only call api if value has changed
		if(faceid && (updatename != $(this).attr("data-orig"))) {
			
			// chage status bar color
			$("#status_"+faceid).removeClass("status-bad").removeClass("status-good").addClass("status-active");
			
			// set name api call, then change status bar color and update 'only-if-changed' value
			$.post(api_url + "/index/setname?faceid="+faceid+"&name="+encodeURIComponent(updatename), function(data) {
				$('#name_'+faceid).attr("data-orig",updatename);
				$("#status_"+faceid).removeClass("status-bad").removeClass("status-active").addClass("status-good");
			});
			
		}
		
		event.preventDefault();
	});
	
	// HANDLE UPLOADER
	$('#drag-and-drop-zone').dmUploader({ 
		url: api_url+"/index/uploadimage",
		maxFileSize: 15000000, // 15 Megs
		dataType: "json",
		allowedTypes: "image/*",
		extFilter: [
			"jpg", "jpeg", "png", "PNG", "JPG", "JPEG"
		],
		onDragEnter: function(){
			this.addClass('upload-select-active');
		},
		onDragLeave: function(){
			this.removeClass('upload-select-active');
		},
		onInit: function(){
			console.log("Uploader initialized.");
		},
		onComplete: function(){
			// All files in the queue are processed (success or error)
		},
		onNewFile: function(id, file){
			ui_multi_add_file(id, file);
	    },
		onBeforeUpload: function(id){
			// about to start uploading a file
			ui_multi_update_file_status(id, 'uploading', 'Uploading...');
			ui_multi_update_file_progress(id, 0, '', true);
		},
		onUploadCanceled: function(id) {
			// Happens when a file is directly canceled by the user.
			ui_multi_update_file_status(id, 'warning', 'Canceled by User');
			ui_multi_update_file_progress(id, 0, 'warning', false);
		},
		onUploadProgress: function(id, percent){
			// Updating file progress
			ui_multi_update_file_progress(id, percent);
		},
		onUploadSuccess: function(id, data){
			// A file was successfully uploaded
			ui_multi_update_file_status(id, 'success', 'Upload Complete');
			ui_multi_update_file_progress(id, 100, 'success', false);
			console.log("Image uploaded: "+JSON.stringify(data));
			setTimeout(function(){
				$('#uploaderFile'+id).fadeOut("fast");
			} , 200);
			
		},
		onUploadError: function(id, xhr, status, message){
			ui_multi_update_file_status(id, 'danger', message);
			ui_multi_update_file_progress(id, 0, 'danger', false);  
		},
		onFallbackMode: function(){
			// When the browser doesn't support this plugin :(
		},
		onFileSizeError: function(file){
			// File size error
		}
	});
	
	// Handle TEST uploader
	$('#drag-and-drop-zone2').dmUploader({ 
		url: api_url+"/index/testimage",
		multiple: false,
		maxFileSize: 15000000, // 15 Megs
		dataType: "json",
		allowedTypes: "image/*",
		extFilter: [
			"jpg", "jpeg", "png", "PNG", "JPG", "JPEG"
		],
		onDragEnter: function(){
			this.addClass('upload-select-active');
		},
		onDragLeave: function(){
			this.removeClass('upload-select-active');
		},
		onInit: function(){
			console.log("Test Uploader initialized.");
		},
		onComplete: function(){
			// All files in the queue are processed (success or error)
		},
		onNewFile: function(id, file){
			//ui_multi_add_file(id, file);
	    },
		onBeforeUpload: function(id){
			// about to start uploading a file
			//ui_multi_update_file_status(id, 'uploading', 'Uploading...');
			//ui_multi_update_file_progress(id, 0, '', true);
		},
		onUploadCanceled: function(id) {
			// Happens when a file is directly canceled by the user.
			//ui_multi_update_file_status(id, 'warning', 'Canceled by User');
			//ui_multi_update_file_progress(id, 0, 'warning', false);
		},
		onUploadProgress: function(id, percent){
			// Updating file progress
			//ui_multi_update_file_progress(id, percent);
		},
		onUploadSuccess: function(id, data){
			// A file was successfully uploaded
			//ui_multi_update_file_status(id, 'success', 'Upload Complete');
			//ui_multi_update_file_progress(id, 100, 'success', false);
			console.log("Image uploaded: "+JSON.stringify(data));
			setTimeout(function(){
				$('#uploaderFile'+id).fadeOut("fast");
			} , 200);
			
		},
		onUploadError: function(id, xhr, status, message){
			//ui_multi_update_file_status(id, 'danger', message);
			//ui_multi_update_file_progress(id, 0, 'danger', false);  
		},
		onFallbackMode: function(){
			// When the browser doesn't support this plugin :(
		},
		onFileSizeError: function(file){
			// File size error
		}
	});

	
	// call list faces API on page load
	listFaces();
	
});