import matplotlib.pyplot as plt
import csv
import os
import argparse
import yaml
from datetime import datetime
from io import StringIO

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
    """Generate a single chart for the given metric and return SVG content as string"""

    font_size = 12
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

    plt.figure(figsize=(10, 6))
    colors = ['blue', 'red']
    for i in range(len(all_x)):
        if all_x[i]:  # Check if data exists
            color = colors[i] if i < len(colors) else f'C{i}'
            plt.plot(all_x[i], all_metric_values[i], marker='o',
                     label=labels[i], color=color)
            
            if args.annotate_values:
                # Add value annotations at each point
                for x, y in zip(all_x[i], all_metric_values[i]):
                    label = f'{y:.2f}'
                    plt.annotate(label, (x, y), textcoords="offset points", 
                                xytext=(0,10), ha='center', fontsize=font_size,annotation_clip=False)

    
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
    
    plt.xlabel(x_label, fontsize=font_size)
    plt.ylabel(y_label, fontsize=font_size)
    
    # Get chart title from metadata or use default
    chart_title = f'RHDH {metric} vs {x_axis}'
    if metadata and 'metrics' in metadata and metric in metadata['metrics']:
        metric_info = metadata['metrics'][metric]
        if 'title' in metric_info:
            chart_title = metric_info['title']
    
    plt.title(chart_title, fontsize=font_size)
    plt.xscale(x_scale)
    plt.legend(fontsize=font_size, bbox_to_anchor=(1.05, 1), loc='upper left')
    plt.grid(True, which='both', axis='both')
    
    # Set tick font size
    plt.tick_params(axis='both', which='major', labelsize=font_size)
    plt.tick_params(axis='both', which='minor', labelsize=font_size)
    
    plt.tight_layout()
    plt.ylim(bottom=0)
    plt.xlim(left=1.0)

    # Save to StringIO buffer as SVG
    svg_buffer = StringIO()
    plt.savefig(svg_buffer, format='svg')
    plt.close()  # Close the figure to free memory

    # Get SVG content and return it
    svg_content = svg_buffer.getvalue()
    svg_buffer.close()
    return svg_content


def generate_html_summary(chart_data, labels, output_dir, metadata=None):
    """Generate HTML summary page with embedded SVG charts in 2-column table layout"""
    html_content = f'''<!DOCTYPE html>
<html lang="en">
<head>
    <meta charset="UTF-8">
    <meta name="viewport" content="width=device-width, initial-scale=1.0">
    <title>RHDH Performance Comparison Summary</title>
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
            grid-template-columns: 1fr 1fr;
            gap: 20px;
            max-width: 1400px;
            margin: 0 auto;
        }}
        .chart-item {{
            background-color: white;
            padding: 15px;
            border-radius: 8px;
            box-shadow: 0 2px 4px rgba(0,0,0,0.1);
            text-align: center;
        }}
        .chart-item svg {{
            max-width: 100%;
            height: auto;
            border: 1px solid #ddd;
            border-radius: 4px;
        }}
        .chart-title {{
            margin-bottom: 10px;
            font-size: 16px;
            font-weight: bold;
            color: #333;
        }}
        .comparison-info {{
            margin-bottom: 20px;
            padding: 10px;
            background-color: #e8f4f8;
            border-left: 4px solid #0066cc;
            border-radius: 4px;
        }}
        @media (max-width: 768px) {{
            .charts-container {{
                grid-template-columns: 1fr;
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
    </div>
    
    <div class="charts-container">
'''

    for metric_name, svg_content in chart_data:
        # Get display title from metadata or use metric name
        display_name = metric_name
        if metadata and 'metrics' in metadata and metric_name in metadata['metrics']:
            metric_info = metadata['metrics'][metric_name]
            if 'title' in metric_info:
                display_name = metric_info['title']

        html_content += f'''
        <div class="chart-item">
            <div class="chart-title">{display_name}</div>
            {svg_content}
        </div>
'''

    html_content += '''
    </div>
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
        svg_content = generate_chart(
            metric, csv_files, labels, x_axis, x_scale, metadata)
        chart_data.append((metric, svg_content))
        print(f"  Chart generated for {metric}")
    except Exception as e:
        print(f"  Error generating chart for {metric}: {e}")

if generate_html and chart_data:
    print("Generating HTML summary with embedded SVG charts...")
    html_path = generate_html_summary(chart_data, labels, output_dir, metadata)
    print(f"HTML summary saved: {html_path}")

print(f"\nSummary:")
print(f"  Generated {len(chart_data)} chart(s)")
if generate_html and chart_data:
    scenario_prefix = args.scenario.replace(' ', '_')
    print(
        f"  Single HTML file with embedded charts: {os.path.join(output_dir, f'{scenario_prefix}_summary.html')}")
print(f"  Output directory: {output_dir}")
