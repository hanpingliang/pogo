
// Note: this file is auto-generated by meta_join.js. Don't Modify me !
YUI().use(function(Y) {

        /**
        * YUI 3 module metadata
        * @module pogo-loader
         */
        var CONFIG = {
                groups: {
                        'pogo': {
                                base: '/pogo/js/build/',
                                combine: false,
                                modules: {"pogo-app":{"path":"pogo-app/pogo-app-min.js","requires":["base","app","pogo-view-dashboard","pogo-view-user","pogo-view-job","pogo-view-host","pogo-model-job"]},"pogo-formatters":{"path":"pogo-formatters/pogo-formatters-min.js","requires":["escape","pogo-env","datatype-date"]},"pogo-model-host":{"path":"pogo-model-host/pogo-model-host-min.js","requires":["base","model"]},"pogo-model-hostslist":{"path":"pogo-model-hostslist/pogo-model-hostslist-min.js","requires":["base","model-list","pogo-model-host"]},"pogo-env":{"path":"pogo-env/pogo-env-min.js","requires":[]},"pogo-model-job":{"path":"pogo-model-job/pogo-model-job-min.js","requires":["base","model","pogo-env","json-parse","jsonp"]},"pogo-model-jobslist":{"path":"pogo-model-jobslist/pogo-model-jobslist-min.js","requires":["base","model-list","pogo-env","querystring-stringify","jsonp","pogo-model-job"]},"pogo-view-dashboard":{"path":"pogo-view-dashboard/pogo-view-dashboard-min.js","requires":["base","pogo-view-multidatatable"]},"pogo-view-host":{"path":"pogo-view-host/pogo-view-host-min.js","requires":["base","view","pogo-view-jobmetadata","pogo-view-hostlog"]},"pogo-view-hostlog":{"path":"pogo-view-hostlog/pogo-view-hostlog-min.js","requires":["base","view"]},"pogo-view-job":{"path":"pogo-view-job/pogo-view-job-min.js","requires":["base","view","pogo-model-hostslist","pogo-view-jobmetadata","pogo-view-jobhostdata"]},"pogo-view-jobhostdata":{"path":"pogo-view-jobhostdata/pogo-view-jobhostdata-min.js","requires":["base","view"]},"pogo-view-jobmetadata":{"path":"pogo-view-jobmetadata/pogo-view-jobmetadata-min.js","requires":["base","view"]},"pogo-view-multidatatable":{"path":"pogo-view-multidatatable/pogo-view-multidatatable-min.js","requires":["base","view","datatable","pogo-model-jobslist","tabview","pogo-formatters","gallery-paginator-dev-preview"]},"pogo-view-user":{"path":"pogo-view-user/pogo-view-user-min.js","requires":["base","pogo-view-multidatatable"]}}
                        }
                }
        };

        if(typeof YUI_config === 'undefined') { YUI_config = {groups:{}}; }
        Y.mix(YUI_config.groups, CONFIG.groups);

});