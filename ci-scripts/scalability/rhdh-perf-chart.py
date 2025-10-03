import plotly.graph_objects as go
import plotly.offline as pyo
from plotly.subplots import make_subplots
import csv
import os
import argparse
import yaml
from datetime import datetime

# Parse command line arguments
parser = argparse.ArgumentParser(
    description='Generate RHDH performance charts from CSV files',
    formatter_class=argparse.RawDescriptionHelpFormatter,
    epilog='''
Examples:
  # Generate chart for a single metric using explicit CSV files
  rhdh-perf-chart.py --previous v1.6.3_summary.csv --current v1.7-122_summary.csv --metric RHDH_Memory_Avg
  
  # Generate charts for current version only (no comparison)
  rhdh-perf-chart.py --current v1.7-122_summary.csv --output-dir ./charts
  
  # Generate charts using directories (summary.csv will be auto-appended)
  rhdh-perf-chart.py --previous /path/to/v1.6.3/results --current /path/to/v1.7-122/results --metrics RHDH_Memory_Avg RHDH_CPU_Avg --x-axis RBAC_POLICY_SIZE --x-scale log --output-dir ./charts
  
  # Auto-detect and generate charts for all numeric columns with single HTML file containing embedded SVG charts
  rhdh-perf-chart.py --previous v1.6.3_summary.csv --current v1.7-122_summary.csv --output-dir ./charts
  
  # Generate only chart data without HTML output using mixed inputs (file + directory)
  rhdh-perf-chart.py --previous v1.6.3_summary.csv --current /path/to/v1.7-122/results --metrics RHDH_Memory_Avg RHDH_CPU_Avg --no-html
  
  # Generate charts with value annotations at data points
  rhdh-perf-chart.py --previous v1.6.3_summary.csv --current v1.7-122_summary.csv --annotate-values --output-dir ./charts
  
  # Generate charts with annotations and specific metrics
  rhdh-perf-chart.py --previous v1.6.3_summary.csv --current v1.7-122_summary.csv --metrics RHDH_Memory_Avg RHDH_CPU_Avg --annotate-values --x-scale log
  
  # Generate charts with custom metadata for labels and units
  rhdh-perf-chart.py --previous v1.6.3_summary.csv --current v1.7-122_summary.csv --metrics-metadata rhdh-perf-chart_metric-metadata.yaml --output-dir ./charts
  
  # Generate charts with custom version labels for plot legends
  rhdh-perf-chart.py --previous v1.6.3_summary.csv --current v1.7-122_summary.csv --previous-version "v1.6.3 (Baseline)" --current-version "v1.7-122 (Latest)" --output-dir ./charts
  
YAML metadata format:
  metrics:
    RHDH_Memory_Avg:
      title: "RHDH Memory Consumption"
      label: "Memory Usage"
      units: "MiB"
    RHDH_CPU_Avg:
      title: "RHDH CPU Utilization"
      label: "CPU Usage"
      units: "%"
    '''
)

parser.add_argument('--previous',
                    help='Previous version CSV file or directory (e.g., v1.6.3_summary.csv or /path/to/results/ - will auto-append summary.csv if directory). Optional - if not provided, only current data will be plotted.')
parser.add_argument('--current', required=True,
                    help='Current version CSV file or directory (e.g., v1.7-122_summary.csv or /path/to/results/ - will auto-append summary.csv if directory)')
parser.add_argument('--metric',
                    help='Name of the column in CSV to plot on y-axis (e.g., RHDH_Memory_Avg, RHDH_CPU_Avg). If not specified, charts will be generated for all numeric columns.')
parser.add_argument('--metrics', nargs='+',
                    help='Multiple metrics to generate charts for (e.g., --metrics RHDH_Memory_Avg RHDH_CPU_Avg)')
parser.add_argument('--x-axis', default='RBAC_POLICY_SIZE',
                    help='Name of the column in CSV to plot on x-axis (default: RBAC_POLICY_SIZE)')
parser.add_argument('--scenario', default='RHDH Scalability',
                    help='Name of the scenario (default: RHDH Scalability)')
parser.add_argument('--x-scale', choices=['linear', 'log'], default='linear',
                    help='Scale for x-axis: linear or log (default: linear)')
parser.add_argument('--output-dir', default='.',
                    help='Directory to save the HTML file with embedded charts (default: current directory)')
parser.add_argument('--generate-html', action='store_true', default=True,
                    help='Generate HTML summary page (default: True)')
parser.add_argument('--annotate-values', action='store_true', default=False,
                    help='Show values at the bullets of the plot (default: False)')
parser.add_argument('--no-html', dest='generate_html', action='store_false',
                    help='Do not generate HTML summary page')
parser.add_argument('--x-label', default='',
                    help='Label for x-axis (default: empty)')
parser.add_argument('--metrics-metadata', default='rhdh-perf-chart_metric-metadata.yaml',
                    help='YAML file containing metric metadata (labels and units for y-axis metrics) (default: rhdh-perf-chart_metric-metadata.yaml)')
parser.add_argument('--current-version',
                    help='Label for current version in plots (if not provided, version will be extracted from file path)')
parser.add_argument('--previous-version',
                    help='Label for previous version in plots (if not provided, version will be extracted from file path)')


args = parser.parse_args()

# Function to normalize input paths - add summary.csv if it's a directory


def normalize_csv_path(path):
    if path.endswith('summary.csv'):
        return path
    elif os.path.isfile(path) and path.endswith('.csv'):
        # It's a CSV file, return as is
        return path
    else:
        # Assume it's a directory and add summary.csv
        return os.path.join(path, 'summary.csv')


def load_metadata(metadata_file):
    """Load metric metadata from YAML file"""
    if not metadata_file or not os.path.exists(metadata_file):
        return {}

    try:
        with open(metadata_file, 'r') as f:
            metadata = yaml.safe_load(f)
        return metadata or {}
    except (yaml.YAMLError, IOError) as e:
        print(f"Warning: Could not load metadata from {metadata_file}: {e}")
        return {}


# Load metadata if provided
metadata = load_metadata(args.metrics_metadata)

# Normalize the input paths
current_csv = normalize_csv_path(args.current)
csv_files = [current_csv]

if args.previous:
    previous_csv = normalize_csv_path(args.previous)
    # Insert at beginning for consistent ordering
    csv_files.insert(0, previous_csv)
x_axis = args.x_axis
x_scale = args.x_scale
output_dir = args.output_dir
generate_html = args.generate_html

# Create output directory if it doesn't exist
os.makedirs(output_dir, exist_ok=True)

# Determine which metrics to process
metrics_to_process = []
if args.metrics:
    metrics_to_process = args.metrics
elif args.metric:
    metrics_to_process = [args.metric]
else:
    # Auto-detect numeric columns from the first CSV file
    with open(csv_files[0], newline='') as csvfile:
        reader = csv.DictReader(csvfile)
        sample_row = next(reader)
        for column_name, value in sample_row.items():
            if column_name != x_axis:  # Skip the x-axis column
                try:
                    float(value)
                    metrics_to_process.append(column_name)
                except (ValueError, TypeError):
                    continue


def extract_version(filename):
    # Extract only the version from the parent directory name (between the scenario and the last dot)
    parent = os.path.basename(os.path.dirname(filename))
    parts = parent.split('.')
    if len(parts) >= 4:
        # .artifacts.<scenario>.<version>.<timestamp>
        # version is everything after the scenario (parts[2]) up to the last dot
        version = '.'.join(parts[3:-1])
        return version
    return parent


def generate_chart(metric, csv_files, labels, x_axis, x_scale, metadata=None):
    """Generate a single interactive chart for the given metric and return HTML content as string"""

    all_x = []
    all_metric_values = []

    for file in csv_files:
        x_vals = []
        metric_values = []
        with open(file, newline='') as csvfile:
            reader = csv.DictReader(csvfile)
            for row in reader:
                try:
                    x_val = float(row[x_axis])
                    value = float(row[metric])
                    # Convert memory from bytes to MB if metric is memory
                    if 'memory' in metric.lower():
                        value = value / (1024 * 1024)
                    x_vals.append(x_val)
                    metric_values.append(value)
                except (KeyError, ValueError):
                    continue

        # Sort values by x-axis
        if x_vals:
            sorted_pairs = sorted(zip(x_vals, metric_values))
            x_vals, metric_values = zip(*sorted_pairs)
            x_vals = list(x_vals)
            metric_values = list(metric_values)

        all_x.append(x_vals)
        all_metric_values.append(metric_values)

    # Create the plotly figure
    fig = go.Figure()

    colors = ['#1f77b4', '#ff7f0e']  # Blue and orange colors
    for i in range(len(all_x)):
        if all_x[i]:  # Check if data exists
            color = colors[i] if i < len(
                colors) else f'hsl({i*137.5}, 50%, 50%)'

            # Create hover text with values
            hover_text = []
            for x, y in zip(all_x[i], all_metric_values[i]):
                hover_text.append(f'{x_axis}: {x}<br>{metric}: {y:.2f}')

            fig.add_trace(go.Scatter(
                x=all_x[i],
                y=all_metric_values[i],
                mode='lines+markers',
                name=labels[i],
                line=dict(color=color, width=2),
                marker=dict(size=8, color=color),
                hovertemplate='%{text}<extra></extra>',
                text=hover_text,
                showlegend=True
            ))

            if args.annotate_values:
                # Add value annotations at each point
                annotations = []
                for x, y in zip(all_x[i], all_metric_values[i]):
                    annotations.append(
                        dict(
                            x=x,
                            y=y,
                            text=f'{y:.2f}',
                            showarrow=True,
                            arrowhead=2,
                            arrowsize=1,
                            arrowwidth=1,
                            arrowcolor=color,
                            ax=0,
                            ay=-30,
                            font=dict(size=10, color=color)
                        )
                    )
                fig.update_layout(annotations=annotations)

    # Use x-label from command line arguments or default to x_axis column name
    x_label = args.x_label if args.x_label else x_axis

    # Get y-axis label and units from metadata
    y_label = metric
    if metadata and 'metrics' in metadata and metric in metadata['metrics']:
        metric_info = metadata['metrics'][metric]
        if 'label' in metric_info:
            y_label = metric_info['label']
        if 'units' in metric_info:
            y_label += f" [{metric_info['units']}]"

    # Get chart title from metadata or use default
    chart_title = f'RHDH {metric} vs {x_axis}'
    if metadata and 'metrics' in metadata and metric in metadata['metrics']:
        metric_info = metadata['metrics'][metric]
        if 'title' in metric_info:
            chart_title = metric_info['title']

    # Update layout
    fig.update_layout(
        title=dict(
            text=chart_title,
            font=dict(size=26),
            x=0.5,
            y=0.94,
            xanchor='center'
        ),
        xaxis=dict(
            title=x_label,
            type='log' if x_scale == 'log' else 'linear',
            showgrid=True,
            gridcolor='lightgray',
            gridwidth=1
        ),
        yaxis=dict(
            title=y_label,
            showgrid=True,
            gridcolor='lightgray',
            gridwidth=1,
            zeroline=True,
            zerolinecolor='black',
            zerolinewidth=1
        ),
        legend=dict(
            x=1.02,
            y=1,
            xanchor='left',
            yanchor='top'
        ),
        hovermode='closest',
        autosize=True,
        width=None,  # Let CSS control the width
        height=500,  # Fixed height
        margin=dict(l=60, r=100, t=60, b=60)
    )

    # Set axis ranges
    if all_x and all_metric_values:
        x_max = max(max(x) for x in all_x if x)
        y_max = max(max(y) for y in all_metric_values if y)
        xaxis_min = 0
        if x_scale == 'log':
            # For log scale, ensure we have reasonable bounds
            # Use powers of 10 that encompass the data range
            import math
            xaxis_max = math.trunc(math.log10(x_max))+1.0
        else:
            # For linear scale, use linear range calculation
            xaxis_max = x_max * 1.1

        fig.update_xaxes(range=[xaxis_min, xaxis_max])
        fig.update_yaxes(range=[0, y_max * 1.1])

    # Convert to HTML div with responsive configuration and custom download filename
    # Create a safe filename from the chart title and x-axis
    safe_title = chart_title.replace(
        ' ', '_').replace(':', '').replace('/', '_')
    safe_x_axis = x_axis.replace(' ', '_').replace(':', '').replace('/', '_')
    filename = f"{safe_title}-{safe_x_axis}"

    config = {
        'responsive': True,
        'displayModeBar': True,
        'toImageButtonOptions': {
            'format': 'png',
            'filename': filename,
            'height': 500,
            'width': 800,
            'scale': 1
        }
    }
    html_div = pyo.plot(fig, output_type='div',
                        include_plotlyjs=False, config=config)
    return html_div


def generate_html_summary(chart_data, labels, output_dir, metadata=None):
    """Generate HTML summary page with embedded interactive Plotly charts in 2-column table layout"""

    # Generate Plotly.js script tag
    plotly_js = pyo.get_plotlyjs()

    html_content = f'''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>RHDH Performance Comparison Summary</title>
    <script src="https://cdn.plot.ly/plotly-latest.min.js"></script>
    <script src="https://cdnjs.cloudflare.com/ajax/libs/jszip/3.10.1/jszip.min.js"></script>
    <style>
        body {{
            font-family: Arial, sans-serif;
            margin: 20px;
            background-color: #f5f5f5;
        }}
        .header {{
            text-align: center;
            margin-bottom: 30px;
            padding: 20px;
            background-color: white;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }}
        .charts-container {{
            display: grid;
            grid-template-columns: repeat(auto-fit, minmax(600px, 800px));
            gap: 20px;
            max-width: 95vw;
            margin: 0 auto;
            padding: 0 20px;
            justify-content: center;
        }}
        .chart-item {{
            background-color: white;
            padding: 15px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            text-align: center;
            width: 100%;
            box-sizing: border-box;
        }}
        .chart-item .plotly {{
            width: 100% !important;
            height: 500px !important;
            border: 1px solid #ddd;
            border-radius: 4px;
            min-width: 0;
            max-width: 100%;
            overflow: hidden;
        }}
        .plotly-graph-div {{
            width: 100% !important;
            height: 500px !important;
            min-width: 0;
            max-width: 100%;
        }}
        .plotly .main-svg {{
            width: 100% !important;
            height: 100% !important;
        }}
        .chart-title {{
            margin-bottom: 10px;
            font-size: 0px;
            font-weight: bold;
            color: #fff;
        }}
        .comparison-info {{
            margin-bottom: 20px;
            padding: 10px;
            background-color: #e8f4f8;
            border-left: 4px solid #0066cc;
            border-radius: 4px;
        }}
        .download-section {{
            margin-bottom: 20px;
            text-align: center;
        }}
        .download-btn {{
            background-color: #0066cc;
            color: white;
            border: none;
            padding: 12px 24px;
            font-size: 16px;
            border-radius: 6px;
            cursor: pointer;
            transition: background-color 0.3s ease;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
        }}
        .download-btn:hover {{
            background-color: #0052a3;
        }}
        .download-btn:active {{
            transform: translateY(1px);
            box-shadow: 0 1px 2px rgba(0,0,0,0.1);
        }}
        .download-btn:disabled {{
            background-color: #ccc;
            cursor: not-allowed;
        }}
        @media (max-width: 768px) {{
            .charts-container {{
                grid-template-columns: 1fr;
                max-width: 100vw;
                padding: 0 10px;
            }}
            .chart-item .plotly {{
                height: 400px;
            }}
        }}
        @media (max-width: 480px) {{
            .charts-container {{
                padding: 0 5px;
            }}
            .chart-item {{
                padding: 10px;
            }}
            .chart-item .plotly {{
                height: 350px;
            }}
        }}
    </style>
</head>
<body>
    <div class="header">
        <h1>RHDH Performance {'Comparison' if len(labels) > 1 else 'Report'} Summary</h1>
        <div class="comparison-info">
            <strong>Scenario:</strong> {args.scenario}<br>
            <strong>{'Comparing RHDH Versions' if len(labels) > 1 else 'RHDH Version'}:</strong> {labels[0] + (' vs ' + labels[1] if len(labels) > 1 else '')}<br>
            <!--strong>Generated:</strong> {datetime.now().strftime("%Y-%m-%d %H:%M:%S")}-->
        </div>
        <div class="download-section">
            <button class="download-btn" onclick="downloadAllCharts()">📦 Download All Charts as ZIP</button>
        </div>
    </div>
    
    <div class="charts-container">
'''

    for metric_name, chart_html in chart_data:
        # Get display title from metadata or use metric name
        display_name = metric_name
        if metadata and 'metrics' in metadata and metric_name in metadata['metrics']:
            metric_info = metadata['metrics'][metric_name]
            if 'title' in metric_info:
                display_name = metric_info['title']

        # Get the chart title that would be used for individual downloads
        chart_title = f'RHDH {metric_name} vs {x_axis}'
        if metadata and 'metrics' in metadata and metric_name in metadata['metrics']:
            metric_info = metadata['metrics'][metric_name]
            if 'title' in metric_info:
                chart_title = metric_info['title']
        
        # Create safe filename like individual downloads
        safe_title = chart_title.replace(' ', '_').replace(':', '').replace('/', '_')
        safe_x_axis = x_axis.replace(' ', '_').replace(':', '').replace('/', '_')
        download_filename = f"{safe_title}-{safe_x_axis}.png"

        html_content += f'''
        <div class="chart-item" data-chart-title="{display_name}" data-download-filename="{download_filename}">
            <div class="chart-title">{display_name}</div>
            {chart_html}
        </div>
'''

    html_content += '''
    </div>
    
    <script>
        // Auto-scale charts on page load and window resize
        function autoScaleCharts() {
            var charts = document.querySelectorAll('.plotly-graph-div');
            charts.forEach(function(chart) {
                if (chart.data) {
                    // Get the container dimensions
                    var container = chart.parentElement;
                    var containerWidth = container.offsetWidth;
                    var containerHeight = container.offsetHeight;
                    
                    // Only resize if container has valid dimensions
                    if (containerWidth > 0 && containerHeight > 0) {
                        // Update the chart size to match container
                        Plotly.Plots.resize(chart);
                        
                        // Force a redraw to ensure proper scaling
                        Plotly.redraw(chart);
                    }
                }
            });
        }
        
        // Download all charts as a ZIP file
        function downloadAllCharts() {
            var button = document.querySelector('.download-btn');
            var originalText = button.innerHTML;
            button.disabled = true;
            button.innerHTML = '⏳ Creating ZIP...';
            
            var charts = document.querySelectorAll('.plotly-graph-div');
            var zip = new JSZip();
            var downloadPromises = [];
            
            charts.forEach(function(chart, index) {
                if (chart.data) {
                    var promise = Plotly.toImage(chart, {
                        format: 'png',
                        width: 800,
                        height: 500,
                        scale: 2
                    }).then(function(dataUrl) {
                        // Get the download filename that matches individual chart downloads
                        var chartTitle = 'Chart_' + (index + 1);
                        
                        // First try to get the pre-calculated download filename (matches individual downloads)
                        // Need to find the chart-item element that contains the data attributes
                        var chartItem = chart.closest('.chart-item');
                        if (chartItem && chartItem.getAttribute('data-download-filename')) {
                            chartTitle = chartItem.getAttribute('data-download-filename').replace('.png', '');
                        }
                        // Fallback to chart title from data attribute
                        else if (chartItem && chartItem.getAttribute('data-chart-title')) {
                            chartTitle = chartItem.getAttribute('data-chart-title').replace(/[^a-zA-Z0-9]/g, '_');
                        }
                        // Try to get title from chart-title div (even if invisible)
                        else if (chartItem) {
                            var titleElement = chartItem.querySelector('.chart-title');
                            if (titleElement && titleElement.textContent.trim()) {
                                chartTitle = titleElement.textContent.trim().replace(/[^a-zA-Z0-9]/g, '_');
                            }
                        }
                        // Try to get title from chart's layout title
                        if (chartTitle === 'Chart_' + (index + 1) && chart.layout && chart.layout.title && chart.layout.title.text) {
                            chartTitle = chart.layout.title.text.replace(/[^a-zA-Z0-9]/g, '_');
                        }
                        // Try to get title from chart's data trace name
                        if (chartTitle === 'Chart_' + (index + 1) && chart.data && chart.data[0] && chart.data[0].name) {
                            chartTitle = chart.data[0].name.replace(/[^a-zA-Z0-9]/g, '_');
                        }
                        
                        // Convert data URL to binary data
                        var base64Data = dataUrl.split(',')[1];
                        var binaryData = atob(base64Data);
                        var bytes = new Uint8Array(binaryData.length);
                        for (var i = 0; i < binaryData.length; i++) {
                            bytes[i] = binaryData.charCodeAt(i);
                        }
                        
                        // Add to ZIP file
                        zip.file(chartTitle + '.png', bytes);
                    });
                    downloadPromises.push(promise);
                }
            });
            
            // Wait for all charts to be processed, then create and download ZIP
            Promise.all(downloadPromises).then(function() {
                button.innerHTML = '⏳ Generating ZIP...';
                
                // Generate ZIP file
                zip.generateAsync({type: 'blob'}).then(function(content) {
                    // Create download link for ZIP file
                    var link = document.createElement('a');
                    link.download = 'RHDH_Performance_Charts.zip';
                    link.href = URL.createObjectURL(content);
                    document.body.appendChild(link);
                    link.click();
                    document.body.removeChild(link);
                    
                    // Clean up the object URL
                    setTimeout(function() {
                        URL.revokeObjectURL(link.href);
                    }, 100);
                    
                    button.innerHTML = '✅ ZIP Downloaded!';
                    setTimeout(function() {
                        button.disabled = false;
                        button.innerHTML = originalText;
                    }, 2000);
                }).catch(function(error) {
                    console.error('Error creating ZIP:', error);
                    button.innerHTML = '❌ ZIP Creation Failed';
                    setTimeout(function() {
                        button.disabled = false;
                        button.innerHTML = originalText;
                    }, 2000);
                });
            }).catch(function(error) {
                console.error('Error processing charts:', error);
                button.innerHTML = '❌ Processing Failed';
                setTimeout(function() {
                    button.disabled = false;
                    button.innerHTML = originalText;
                }, 2000);
            });
        }
        
        // Auto-scale on page load
        window.addEventListener('load', function() {
            // Multiple attempts to ensure charts are properly scaled
            setTimeout(autoScaleCharts, 50);
            setTimeout(autoScaleCharts, 200);
            setTimeout(autoScaleCharts, 500);
        });
        
        // Auto-scale on window resize with debouncing
        var resizeTimeout;
        window.addEventListener('resize', function() {
            clearTimeout(resizeTimeout);
            resizeTimeout = setTimeout(autoScaleCharts, 100);
        });
        
        // Auto-scale when DOM is ready (fallback)
        if (document.readyState === 'loading') {
            document.addEventListener('DOMContentLoaded', function() {
                setTimeout(autoScaleCharts, 100);
            });
        } else {
            // DOM is already ready
            setTimeout(autoScaleCharts, 100);
        }
    </script>
</body>
</html>
'''

    scenario_prefix = args.scenario.replace(' ', '_')
    html_path = os.path.join(output_dir, f'{scenario_prefix}_summary.html')
    with open(html_path, 'w', encoding='utf-8') as f:
        f.write(html_content)

    return html_path


# Main execution
# Create labels using provided version arguments or extract from file paths
labels = []
for i, f in enumerate(csv_files):
    if i == 0 and args.previous and args.previous_version:
        # First file is previous version
        labels.append(args.previous_version)
    elif (i == 1 and args.current and args.current_version) or (i == 0 and not args.previous and args.current and args.current_version):
        # Second file is current version (when comparing) OR first file is current version (when no comparison)
        labels.append(args.current_version)
    else:
        # Fallback to extracting version from file path
        labels.append(extract_version(f))
chart_data = []

print(f"Processing {len(metrics_to_process)} metrics...")

for metric in metrics_to_process:
    try:
        print(f"Generating chart for {metric}...")
        chart_html = generate_chart(
            metric, csv_files, labels, x_axis, x_scale, metadata)
        chart_data.append((metric, chart_html))
        print(f"  Chart generated for {metric}")
    except Exception as e:
        print(f"  Error generating chart for {metric}: {e}")

if generate_html and chart_data:
    print("Generating HTML summary with embedded interactive charts...")
    html_path = generate_html_summary(chart_data, labels, output_dir, metadata)
    print(f"HTML summary saved: {html_path}")

print(f"\nSummary:")
print(f"  Generated {len(chart_data)} chart(s)")
if generate_html and chart_data:
    scenario_prefix = args.scenario.replace(' ', '_')
    print(
        f"  Single HTML file with embedded charts: {os.path.join(output_dir, f'{scenario_prefix}_summary.html')}")
print(f"  Output directory: {output_dir}")
