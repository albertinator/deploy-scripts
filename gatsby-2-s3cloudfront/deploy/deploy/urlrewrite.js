// rewrite the URL to direct to index.html for permalinks

'use strict';
exports.handler = (event, context, callback) => {
  // Extract the request from the CloudFront event that is sent to Lambda@Edge 
  var request = event.Records[0].cf.request;

  // Extract the URI from the request
  var olduri = request.uri;
  var newuri = '';
  var noRewriteRegex = /.*\.(html|css|map|js|woff2|woff|png|jpeg|jpg|gif|svg|ico|pdf|xml|webmanifest|json)$/g;

  if ( !olduri.match(noRewriteRegex) ) {
    if ( olduri.substr(olduri.length - 1) === '/' ) {
      newuri = olduri + 'index.html';
    } else {
      newuri = olduri + '/index.html';
    }
  } else {
    newuri = olduri;
  }

  // Match any '/' that occurs at the end of a URI. Replace it with a default index
  // var newuri = olduri.replace(/\/$/, '\/index.html');

  // Log the URI as received by CloudFront and the new URI to be used to fetch from origin
  console.log("Old URI: " + olduri);
  console.log("New URI: " + newuri);

  // Replace the received URI with the URI that includes the index page
  request.uri = newuri;

  // Return to CloudFront
  return callback(null, request);
};
