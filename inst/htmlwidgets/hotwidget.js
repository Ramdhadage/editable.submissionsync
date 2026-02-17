HTMLWidgets.widget({

  name: 'hotwidget',

  type: 'output',

  factory: function(el, width, height) {

    let hotInstance = null;
    let currentData = null;
    let isUpdating = false;


    return {

      renderValue: function(x) {

        // TODO: code to render the widget, e.g.
        currentData = HTMLWidgets.dataframeToD3(x.data);
        const originalColHeaders = x.colHeaders || Object.keys(currentData[0] || {});
        const colHeaders = originalColHeaders.map((header) => header.toUpperCase());
        const colTypes = x.colTypes || {};
        if (hotInstance) {
          hotInstance.destroy();
          hotInstance = null;
        }
        el.innerText = "";
        const colWidths = x.colWidths || null;
        const rowHeights = x.rowHeights || 'auto';
        hotInstance = new Handsontable(el, {
          themeName: 'ht-theme-main',
          data: currentData,
          colHeaders: colHeaders,
          className: 'htCenter',
          rowHeaders: false,
          columnSorting: true,
          filters: true,
          dropdownMenu: true,
          manualColumnResize: true,
          contextMenu: true,
          search : true,
          stretchH: 'all',
         // colWidths: colWidths,
          rowHeights: rowHeights,
          autoRowSize: x.autoRowSize !== undefined ? x.autoRowSize : false,
          pagination: {
            pageSize: 50,
            pageSizeList: ['auto', 5, 10, 20, 50, 100],
            initialPage: 1,
            showPageSize: true,
            showCounter: true,
            showNavigation: true,
          },
           columns: originalColHeaders.map((colName) => {
            const colType = colTypes[colName];
            const config = { data: colName };

            if (colName === 'MODEL') {
              config.readOnly = true;
            }
            switch(colType) {
              case 'numeric':
                config.type = 'numeric';
                config.numericFormat = {
                  pattern: '0,0.00'
                };
                break;

              case 'integer':
                config.type = 'numeric';
                config.numericFormat = {
                  pattern: '0,0'
                };
                break;

              case 'character':
                config.type = 'text';
                break;

             case 'logical':
                config.type = 'checkbox';
                break;
             case 'factor':
                config.type = 'select';
                config.selectOptions = [...new Set(x.data[colName])];
                break;
            default:
                config.type = 'text';
            }
            return config;
          }),
/**
           * afterChange Hook - Capture cell edits and send to R
           *
           * Implements single-cell edit pattern:
           * 1. User edits cell in Handsontable
           * 2. JS validates type (numeric, text, etc.)
           * 3. Send edit to R via Shiny.setInputValue
           * 4. R validates and updates R6 state
           * 5. R re-renders widget with new data
           *
           * @param {Array} changes - Array of changes [[row, prop, oldVal, newVal], ...]
           * @param {String} source - Source of change ('edit', 'loadData', etc.)
           */
          afterChange: function(changes, source) {
            if (source === 'loadData' || isUpdating) {
              return;
            }

            if (source !== 'edit' || !changes) {
              return;
            }

            const change = changes[0];
            const [row, prop, oldValue, newValue] = change;

            if (oldValue === newValue) {
              return;
            }

            if (typeof Shiny !== 'undefined') {
              Shiny.setInputValue(el.id + '_edit', {
                row: row,
                col: prop,
                oldValue: oldValue,
                value: newValue,
                timestamp: Date.now()
              });
            }
          },

          /**
           * afterValidate Hook - Show validation errors
           */
          afterValidate: function(isValid, value, row, prop, source) {
            if (!isValid && source === 'edit') {
              console.warn('Validation failed:', {row, col: prop, value});
            }
          },
          licenseKey: 'non-commercial-and-evaluation',
        })

      },

      resize: function(width, height) {

        // TODO: code to re-render the widget with a new size
        if (hotInstance) {

          el.style.width = width + 'px';
          el.style.height = height + 'px';

          hotInstance.updateSettings({
            width: width,
            height: height
          });
        }

      }

    };
  }
});
