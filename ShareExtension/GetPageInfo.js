// JavaScript preprocessing for the Share Extension.
// Safari runs this on the active page and passes the result (url/title/selection)
// to ShareViewController via the property-list attachment.
var GetPageInfo = function() {};
GetPageInfo.prototype = {
    run: function(args) {
        args.completionFunction({
            "url": document.URL,
            "title": document.title,
            "selection": window.getSelection ? window.getSelection().toString() : ""
        });
    },
    finalize: function(args) {}
};
var ExtensionPreprocessingJS = new GetPageInfo;
