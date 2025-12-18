#!/usr/bin/env python3
"""
Advanced Hand-Nose Test Visualization
Creates stunning, publication-ready visualizations for clinical presentation.
"""

import json
import numpy as np
import matplotlib.pyplot as plt
import matplotlib.patches as mpatches
from matplotlib.colors import LinearSegmentedColormap
from matplotlib.patches import FancyBboxPatch, Circle
import seaborn as sns
from scipy import signal, interpolate
from scipy.spatial import distance
from scipy.ndimage import gaussian_filter1d
import warnings
warnings.filterwarnings('ignore')

# Professional styling
sns.set_style("white")
plt.rcParams.update({
    'font.size': 11,
    'font.family': 'sans-serif',
    'font.weight': 'normal',
    'axes.labelsize': 13,
    'axes.titlesize': 16,
    'axes.titleweight': 'bold',
    'xtick.labelsize': 10,
    'ytick.labelsize': 10,
    'legend.fontsize': 10,
    'figure.dpi': 300,
    'savefig.dpi': 300,
    'savefig.bbox': 'tight',
    'savefig.facecolor': 'white',
    'axes.linewidth': 1.2,
    'grid.alpha': 0.3
})

# Custom color palettes
REP_COLORS = plt.cm.Set3(np.linspace(0, 1, 10))
VELOCITY_CMAP = plt.cm.plasma
DEVIATION_CMAP = plt.cm.RdYlGn_r
TREMOR_CMAP = plt.cm.viridis


def load_data(filepath):
    """Load and extract finger tracking data"""
    with open(filepath, 'r') as f:
        data = json.load(f)
    return data['fingers'][0]['points']


def normalize_timestamps(points):
    """Normalize timestamps to start from 0"""
    start_time = points[0]['t']
    return [{**p, 't': p['t'] - start_time} for p in points]


def identify_repetitions(points):
    """
    Smart repetition identification using distance from start and velocity changes.
    """
    x = np.array([p['x'] for p in points])
    y = np.array([p['y'] for p in points])
    t = np.array([p['t'] for p in points])
    
    # Calculate distance from start
    start_x, start_y = x[0], y[0]
    distances_from_start = np.sqrt((x - start_x)**2 + (y - start_y)**2)
    
    # Calculate velocity to detect direction changes
    dt = np.diff(t)
    dt[dt == 0] = 0.001
    vx = np.diff(x) / dt
    vy = np.diff(y) / dt
    v_mag = np.sqrt(vx**2 + vy**2)
    
    # Find local minima in distance (return to start)
    from scipy.signal import find_peaks
    # Invert to find minima
    inv_dist = -distances_from_start
    peaks, properties = find_peaks(inv_dist, distance=len(points)//40, 
                                   prominence=np.max(distances_from_start)*0.1)
    
    # Also use velocity minima (pauses at start/end)
    inv_vel = -v_mag
    vel_peaks, _ = find_peaks(inv_vel, distance=len(v_mag)//40,
                             prominence=np.max(v_mag)*0.1)
    
    # Combine and sort
    all_transitions = sorted(set(list(peaks) + list(vel_peaks + 1)))
    
    # If we don't have enough, use time-based segmentation
    if len(all_transitions) < 10:
        total_time = t[-1]
        segment_time = total_time / 20
        all_transitions = []
        for i in range(1, 21):
            target_time = i * segment_time
            idx = np.argmin(np.abs(t - target_time))
            all_transitions.append(idx)
        all_transitions = sorted(set(all_transitions))
    
    # Organize into repetitions
    repetitions = []
    all_indices = [0] + sorted(all_transitions) + [len(points)-1]
    
    # Group into pairs for each repetition (out and back)
    for i in range(0, min(20, len(all_indices)-1), 2):
        if i+1 < len(all_indices):
            start_idx = all_indices[i]
            mid_idx = all_indices[i+1] if i+1 < len(all_indices) else all_indices[i]
            end_idx = all_indices[i+2] if i+2 < len(all_indices) else len(points)-1
            
            if end_idx > start_idx:
                repetitions.append({
                    'start_idx': start_idx,
                    'mid_idx': mid_idx,
                    'end_idx': end_idx,
                    'points': points[start_idx:end_idx+1]
                })
    
    # Fallback: split evenly if needed
    if len(repetitions) != 10:
        total_points = len(points)
        points_per_rep = total_points // 10
        repetitions = []
        for i in range(10):
            start_idx = i * points_per_rep
            end_idx = (i + 1) * points_per_rep if i < 9 else total_points
            mid_idx = start_idx + (end_idx - start_idx) // 2
            repetitions.append({
                'start_idx': start_idx,
                'mid_idx': mid_idx,
                'end_idx': end_idx,
                'points': points[start_idx:end_idx]
            })
    
    return repetitions[:10]


def calculate_kinematics(points):
    """Calculate comprehensive kinematic data"""
    t = np.array([p['t'] for p in points])
    x = np.array([p['x'] for p in points])
    y = np.array([p['y'] for p in points])
    
    dt = np.diff(t)
    dt[dt == 0] = 0.001
    
    dx = np.diff(x)
    dy = np.diff(y)
    
    vx = dx / dt
    vy = dy / dt
    v_mag = np.sqrt(vx**2 + vy**2)
    
    # Acceleration
    dt2 = dt[:-1]
    dt2[dt2 == 0] = 0.001
    ax = np.diff(vx) / dt2
    ay = np.diff(vy) / dt2
    a_mag = np.sqrt(ax**2 + ay**2)
    
    # Jerk
    dt3 = dt2[:-1]
    dt3[dt3 == 0] = 0.001
    jx = np.diff(ax) / dt3
    jy = np.diff(ay) / dt3
    jerk_mag = np.sqrt(jx**2 + jy**2)
    
    # Curvature
    curvature = np.abs(vx[:-1] * ay - vy[:-1] * ax) / (v_mag[:-1]**3 + 1e-10)
    
    return {
        't': t, 'x': x, 'y': y,
        'vx': vx, 'vy': vy, 'v_mag': v_mag,
        'ax': ax, 'ay': ay, 'a_mag': a_mag,
        'jx': jx, 'jy': jy, 'jerk_mag': jerk_mag,
        'curvature': curvature
    }


def plot_3d_trajectory_with_velocity(points, repetitions, output_file):
    """3D trajectory plot with time as Z-axis and velocity coloring"""
    fig = plt.figure(figsize=(14, 10))
    ax = fig.add_subplot(111, projection='3d')
    
    # Plot each repetition
    for i, rep in enumerate(repetitions):
        rep_points = rep['points']
        x = np.array([p['x'] for p in rep_points])
        y = np.array([p['y'] for p in rep_points])
        t = np.array([p['t'] for p in rep_points])
        
        data = calculate_kinematics(rep_points)
        v_mag = data['v_mag']
        
        # Normalize velocity for coloring
        v_norm = (v_mag - np.min(v_mag)) / (np.max(v_mag) - np.min(v_mag) + 1e-10)
        
        # Plot with velocity coloring
        for j in range(len(x)-1):
            ax.plot([x[j], x[j+1]], [y[j], y[j+1]], [t[j], t[j+1]],
                   color=VELOCITY_CMAP(v_norm[j] if j < len(v_norm) else 0.5),
                   linewidth=2.5, alpha=0.8)
    
    ax.set_xlabel('X Position', fontweight='bold', labelpad=10)
    ax.set_ylabel('Y Position', fontweight='bold', labelpad=10)
    ax.set_zlabel('Time (s)', fontweight='bold', labelpad=10)
    ax.set_title('3D Trajectory: Position Over Time\n(Colored by Velocity)', 
                fontsize=18, fontweight='bold', pad=20)
    
    # Add colorbar
    sm = plt.cm.ScalarMappable(cmap=VELOCITY_CMAP, 
                               norm=plt.Normalize(vmin=0, vmax=1))
    sm.set_array([])
    cbar = plt.colorbar(sm, ax=ax, shrink=0.6, aspect=20, pad=0.1)
    cbar.set_label('Normalized Velocity', fontweight='bold', rotation=270, labelpad=20)
    
    plt.tight_layout()
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    plt.close()
    print(f"✓ Saved: {output_file}")


def plot_trajectory_heatmap_overlay(points, repetitions, output_file):
    """Trajectory with density heatmap background and repetition overlays"""
    fig, ax = plt.subplots(figsize=(14, 12))
    
    # Create density heatmap from all points
    all_x = np.array([p['x'] for p in points])
    all_y = np.array([p['y'] for p in points])
    
    # 2D histogram
    h, xedges, yedges = np.histogram2d(all_x, all_y, bins=150)
    h_smooth = gaussian_filter1d(gaussian_filter1d(h, sigma=2, axis=0), sigma=2, axis=1)
    
    # Plot heatmap
    extent = [xedges[0], xedges[-1], yedges[0], yedges[-1]]
    im = ax.imshow(h_smooth.T, origin='lower', cmap='hot', aspect='auto',
                   extent=extent, alpha=0.6, interpolation='bilinear')
    
    # Plot each repetition with distinct colors
    for i, rep in enumerate(repetitions):
        rep_points = rep['points']
        x = np.array([p['x'] for p in rep_points])
        y = np.array([p['y'] for p in rep_points])
        
        # Plot trajectory
        ax.plot(x, y, color=REP_COLORS[i], linewidth=3, alpha=0.9, 
               label=f'Rep {i+1}', zorder=5)
        
        # Mark start and end
        ax.scatter(x[0], y[0], color=REP_COLORS[i], s=150, marker='o',
                  edgecolors='white', linewidths=2, zorder=6)
        ax.scatter(x[-1], y[-1], color=REP_COLORS[i], s=150, marker='s',
                  edgecolors='white', linewidths=2, zorder=6)
    
    # Mark overall start
    ax.scatter(all_x[0], all_y[0], color='red', s=300, marker='*',
              edgecolors='black', linewidths=3, zorder=7, label='Initial Start')
    
    cbar = plt.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
    cbar.set_label('Position Density', fontweight='bold', rotation=270, labelpad=20)
    
    ax.set_xlabel('X Position (normalized)', fontweight='bold', fontsize=14)
    ax.set_ylabel('Y Position (normalized)', fontweight='bold', fontsize=14)
    ax.set_title('Trajectory Overlay on Movement Density Heatmap', 
                fontsize=18, fontweight='bold', pad=20)
    ax.invert_yaxis()
    ax.set_aspect('equal')
    ax.legend(loc='upper right', ncol=2, fontsize=9, framealpha=0.9)
    ax.grid(True, alpha=0.2, linestyle='--')
    
    plt.tight_layout()
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    plt.close()
    print(f"✓ Saved: {output_file}")


def plot_velocity_vector_field(points, repetitions, output_file):
    """Advanced velocity vector field with magnitude coloring"""
    fig, ax = plt.subplots(figsize=(14, 12))
    
    # Plot all trajectories first
    for i, rep in enumerate(repetitions):
        rep_points = rep['points']
        x = np.array([p['x'] for p in rep_points])
        y = np.array([p['y'] for p in rep_points])
        ax.plot(x, y, color='gray', linewidth=1, alpha=0.3, zorder=1)
    
    # Add velocity vectors
    all_velocities = []
    for rep in repetitions:
        rep_points = rep['points']
        data = calculate_kinematics(rep_points)
        all_velocities.extend(data['v_mag'])
    
    v_min, v_max = np.min(all_velocities), np.max(all_velocities)
    
    for i, rep in enumerate(repetitions):
        rep_points = rep['points']
        x = np.array([p['x'] for p in rep_points])
        y = np.array([p['y'] for p in rep_points])
        data = calculate_kinematics(rep_points)
        
        # Subsample for cleaner visualization
        skip = max(1, len(x) // 30)
        x_sub = x[:-1:skip]
        y_sub = y[:-1:skip]
        vx_sub = data['vx'][::skip]
        vy_sub = data['vy'][::skip]
        v_mag_sub = data['v_mag'][::skip]
        
        # Normalize velocity for color
        v_norm = (v_mag_sub - v_min) / (v_max - v_min + 1e-10)
        
        # Quiver plot
        ax.quiver(x_sub, y_sub, vx_sub, vy_sub, v_mag_sub,
                 cmap=VELOCITY_CMAP, scale=1.0/0.01, scale_units='xy',
                 width=0.003, alpha=0.7, zorder=3)
    
    ax.set_xlabel('X Position (normalized)', fontweight='bold', fontsize=14)
    ax.set_ylabel('Y Position (normalized)', fontweight='bold', fontsize=14)
    ax.set_title('Velocity Vector Field\n(Arrow direction = movement direction, Color = speed)', 
                fontsize=18, fontweight='bold', pad=20)
    ax.invert_yaxis()
    ax.set_aspect('equal')
    ax.grid(True, alpha=0.2, linestyle='--')
    
    # Add colorbar
    sm = plt.cm.ScalarMappable(cmap=VELOCITY_CMAP, 
                               norm=plt.Normalize(vmin=v_min, vmax=v_max))
    sm.set_array([])
    cbar = plt.colorbar(sm, ax=ax, fraction=0.046, pad=0.04)
    cbar.set_label('Velocity Magnitude', fontweight='bold', rotation=270, labelpad=20)
    
    plt.tight_layout()
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    plt.close()
    print(f"✓ Saved: {output_file}")


def plot_deviation_heatmap(points, repetitions, output_file):
    """Deviation from ideal path as a heatmap with trajectory overlay"""
    fig, ax = plt.subplots(figsize=(14, 12))
    
    # Create grid for deviation heatmap
    all_x = np.array([p['x'] for p in points])
    all_y = np.array([p['y'] for p in points])
    
    x_min, x_max = np.min(all_x), np.max(all_x)
    y_min, y_max = np.min(all_y), np.max(all_y)
    
    # Create fine grid
    grid_res = 200
    x_grid = np.linspace(x_min, x_max, grid_res)
    y_grid = np.linspace(y_min, y_max, grid_res)
    X_grid, Y_grid = np.meshgrid(x_grid, y_grid)
    
    # Calculate deviation for each repetition and accumulate
    deviation_grid = np.zeros_like(X_grid)
    
    for rep in repetitions:
        rep_points = rep['points']
        x = np.array([p['x'] for p in rep_points])
        y = np.array([p['y'] for p in rep_points])
        
        # Ideal straight line
        start_x, start_y = x[0], y[0]
        end_x, end_y = x[-1], y[-1]
        dx_ideal = end_x - start_x
        dy_ideal = end_y - start_y
        line_length = np.sqrt(dx_ideal**2 + dy_ideal**2)
        
        if line_length > 0:
            # For each grid point, find closest point on trajectory
            for i in range(grid_res):
                for j in range(grid_res):
                    gx, gy = X_grid[i, j], Y_grid[i, j]
                    
                    # Distance to ideal line
                    dx_curr = gx - start_x
                    dy_curr = gy - start_y
                    t_param = (dx_curr * dx_ideal + dy_curr * dy_ideal) / (line_length**2)
                    t_param = np.clip(t_param, 0, 1)
                    
                    closest_x = start_x + t_param * dx_ideal
                    closest_y = start_y + t_param * dy_ideal
                    
                    dev = np.sqrt((gx - closest_x)**2 + (gy - closest_y)**2)
                    deviation_grid[i, j] += dev
    
    # Smooth the deviation grid
    deviation_grid = gaussian_filter1d(gaussian_filter1d(deviation_grid, sigma=3, axis=0), 
                                      sigma=3, axis=1)
    
    # Plot heatmap
    im = ax.imshow(deviation_grid, origin='lower', cmap=DEVIATION_CMAP,
                   extent=[x_min, x_max, y_min, y_max], alpha=0.7,
                   interpolation='bilinear')
    
    # Overlay trajectories
    for i, rep in enumerate(repetitions):
        rep_points = rep['points']
        x = np.array([p['x'] for p in rep_points])
        y = np.array([p['y'] for p in rep_points])
        ax.plot(x, y, color='white', linewidth=2.5, alpha=0.8, zorder=5)
        ax.plot(x, y, color=REP_COLORS[i], linewidth=1.5, alpha=0.9, zorder=6)
    
    cbar = plt.colorbar(im, ax=ax, fraction=0.046, pad=0.04)
    cbar.set_label('Cumulative Deviation from Ideal Path', fontweight='bold', 
                   rotation=270, labelpad=20)
    
    ax.set_xlabel('X Position (normalized)', fontweight='bold', fontsize=14)
    ax.set_ylabel('Y Position (normalized)', fontweight='bold', fontsize=14)
    ax.set_title('Path Deviation Heatmap\n(Red = High Deviation, Green = Low Deviation)', 
                fontsize=18, fontweight='bold', pad=20)
    ax.invert_yaxis()
    ax.set_aspect('equal')
    ax.grid(True, alpha=0.2, linestyle='--', color='white')
    
    plt.tight_layout()
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    plt.close()
    print(f"✓ Saved: {output_file}")


def plot_phase_space_velocity(points, repetitions, output_file):
    """Phase space plot: velocity X vs velocity Y"""
    fig, ax = plt.subplots(figsize=(14, 12))
    
    for i, rep in enumerate(repetitions):
        rep_points = rep['points']
        data = calculate_kinematics(rep_points)
        
        # Color by time within repetition
        t_norm = (data['t'][:-1] - data['t'][0]) / (data['t'][-1] - data['t'][0] + 1e-10)
        
        # Scatter plot with time coloring
        scatter = ax.scatter(data['vx'], data['vy'], c=t_norm, cmap=plt.cm.viridis,
                           s=30, alpha=0.7, edgecolors='black', linewidths=0.5,
                           label=f'Rep {i+1}', zorder=3)
        
        # Connect points with line
        ax.plot(data['vx'], data['vy'], color=REP_COLORS[i], linewidth=1.5,
               alpha=0.4, zorder=2)
    
    ax.axhline(0, color='black', linestyle='--', linewidth=1, alpha=0.5)
    ax.axvline(0, color='black', linestyle='--', linewidth=1, alpha=0.5)
    
    ax.set_xlabel('Velocity X Component', fontweight='bold', fontsize=14)
    ax.set_ylabel('Velocity Y Component', fontweight='bold', fontsize=14)
    ax.set_title('Phase Space: Velocity Components\n(Colored by Time Within Each Repetition)', 
                fontsize=18, fontweight='bold', pad=20)
    ax.grid(True, alpha=0.3, linestyle='--')
    ax.legend(loc='upper right', ncol=2, fontsize=9, framealpha=0.9)
    ax.set_aspect('equal')
    
    plt.tight_layout()
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    plt.close()
    print(f"✓ Saved: {output_file}")


def plot_frequency_spectrum(points, repetitions, output_file):
    """Frequency domain analysis using FFT"""
    fig, (ax1, ax2) = plt.subplots(2, 1, figsize=(14, 10))
    
    # Calculate average sampling rate
    all_t = np.array([p['t'] for p in points])
    fs = 1 / np.mean(np.diff(all_t))
    
    # X-axis frequency spectrum
    for i, rep in enumerate(repetitions):
        rep_points = rep['points']
        x = np.array([p['x'] for p in rep_points])
        t = np.array([p['t'] for p in rep_points])
        
        # Remove DC component
        x_centered = x - np.mean(x)
        
        # FFT
        fft_x = np.fft.fft(x_centered)
        freqs = np.fft.fftfreq(len(x), 1/fs)
        
        # Only positive frequencies
        pos_mask = freqs > 0
        freqs_pos = freqs[pos_mask]
        power_x = np.abs(fft_x[pos_mask])
        
        # Limit to 0-15 Hz
        mask_15hz = freqs_pos <= 15
        ax1.semilogy(freqs_pos[mask_15hz], power_x[mask_15hz], 
                    color=REP_COLORS[i], linewidth=2, alpha=0.7, label=f'Rep {i+1}')
    
    ax1.set_xlabel('Frequency (Hz)', fontweight='bold', fontsize=12)
    ax1.set_ylabel('Power (log scale)', fontweight='bold', fontsize=12)
    ax1.set_title('X-Axis Frequency Spectrum (0-15 Hz)', fontsize=14, fontweight='bold')
    ax1.grid(True, alpha=0.3, linestyle='--')
    ax1.legend(loc='upper right', ncol=2, fontsize=8)
    ax1.set_xlim([0, 15])
    
    # Y-axis frequency spectrum
    for i, rep in enumerate(repetitions):
        rep_points = rep['points']
        y = np.array([p['y'] for p in rep_points])
        t = np.array([p['t'] for p in rep_points])
        
        y_centered = y - np.mean(y)
        fft_y = np.fft.fft(y_centered)
        freqs = np.fft.fftfreq(len(y), 1/fs)
        
        pos_mask = freqs > 0
        freqs_pos = freqs[pos_mask]
        power_y = np.abs(fft_y[pos_mask])
        
        mask_15hz = freqs_pos <= 15
        ax2.semilogy(freqs_pos[mask_15hz], power_y[mask_15hz],
                    color=REP_COLORS[i], linewidth=2, alpha=0.7, label=f'Rep {i+1}')
    
    ax2.set_xlabel('Frequency (Hz)', fontweight='bold', fontsize=12)
    ax2.set_ylabel('Power (log scale)', fontweight='bold', fontsize=12)
    ax2.set_title('Y-Axis Frequency Spectrum (0-15 Hz)', fontsize=14, fontweight='bold')
    ax2.grid(True, alpha=0.3, linestyle='--')
    ax2.legend(loc='upper right', ncol=2, fontsize=8)
    ax2.set_xlim([0, 15])
    
    plt.suptitle('Frequency Domain Analysis: Tremor Detection', 
                fontsize=18, fontweight='bold', y=0.995)
    plt.tight_layout()
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    plt.close()
    print(f"✓ Saved: {output_file}")


def plot_comprehensive_metrics_dashboard(points, repetitions, output_file):
    """Comprehensive dashboard with multiple metrics"""
    fig = plt.figure(figsize=(16, 12))
    gs = fig.add_gridspec(3, 3, hspace=0.3, wspace=0.3)
    
    # Calculate metrics for each repetition
    metrics = {
        'path_length': [],
        'duration': [],
        'max_deviation': [],
        'mean_velocity': [],
        'max_velocity': [],
        'efficiency': [],
        'mean_jerk': [],
        'mean_curvature': []
    }
    
    for rep in repetitions:
        rep_points = rep['points']
        x = np.array([p['x'] for p in rep_points])
        y = np.array([p['y'] for p in rep_points])
        t = np.array([p['t'] for p in rep_points])
        data = calculate_kinematics(rep_points)
        
        # Path length
        segments = np.sqrt(np.diff(x)**2 + np.diff(y)**2)
        metrics['path_length'].append(np.sum(segments))
        
        # Duration
        metrics['duration'].append(t[-1] - t[0] if len(t) > 1 else 0)
        
        # Max deviation
        start_x, start_y = x[0], y[0]
        end_x, end_y = x[-1], y[-1]
        dx_ideal = end_x - start_x
        dy_ideal = end_y - start_y
        line_length = np.sqrt(dx_ideal**2 + dy_ideal**2)
        
        max_dev = 0
        if line_length > 0:
            for j in range(len(x)):
                dx_curr = x[j] - start_x
                dy_curr = y[j] - start_y
                t_param = (dx_curr * dx_ideal + dy_curr * dy_ideal) / (line_length**2)
                t_param = np.clip(t_param, 0, 1)
                closest_x = start_x + t_param * dx_ideal
                closest_y = start_y + t_param * dy_ideal
                dev = np.sqrt((x[j] - closest_x)**2 + (y[j] - closest_y)**2)
                max_dev = max(max_dev, dev)
        metrics['max_deviation'].append(max_dev)
        
        # Velocities
        metrics['mean_velocity'].append(np.mean(data['v_mag']))
        metrics['max_velocity'].append(np.max(data['v_mag']))
        
        # Efficiency
        actual_length = np.sum(segments)
        straight_length = np.sqrt((x[-1] - x[0])**2 + (y[-1] - y[0])**2)
        efficiency = (straight_length / actual_length * 100) if actual_length > 0 else 0
        metrics['efficiency'].append(efficiency)
        
        # Jerk and curvature
        metrics['mean_jerk'].append(np.mean(data['jerk_mag']))
        metrics['mean_curvature'].append(np.mean(data['curvature']))
    
    rep_nums = np.arange(1, 11)
    
    # Plot 1: Path Length
    ax1 = fig.add_subplot(gs[0, 0])
    ax1.bar(rep_nums, metrics['path_length'], color=REP_COLORS, alpha=0.8, edgecolor='black')
    ax1.set_xlabel('Repetition', fontweight='bold')
    ax1.set_ylabel('Path Length', fontweight='bold')
    ax1.set_title('Path Length', fontweight='bold')
    ax1.grid(True, alpha=0.3, axis='y')
    
    # Plot 2: Duration
    ax2 = fig.add_subplot(gs[0, 1])
    ax2.bar(rep_nums, metrics['duration'], color=REP_COLORS, alpha=0.8, edgecolor='black')
    ax2.set_xlabel('Repetition', fontweight='bold')
    ax2.set_ylabel('Duration (s)', fontweight='bold')
    ax2.set_title('Duration', fontweight='bold')
    ax2.grid(True, alpha=0.3, axis='y')
    
    # Plot 3: Max Deviation
    ax3 = fig.add_subplot(gs[0, 2])
    ax3.bar(rep_nums, metrics['max_deviation'], color=REP_COLORS, alpha=0.8, edgecolor='black')
    ax3.set_xlabel('Repetition', fontweight='bold')
    ax3.set_ylabel('Max Deviation', fontweight='bold')
    ax3.set_title('Max Deviation', fontweight='bold')
    ax3.grid(True, alpha=0.3, axis='y')
    
    # Plot 4: Mean Velocity
    ax4 = fig.add_subplot(gs[1, 0])
    ax4.bar(rep_nums, metrics['mean_velocity'], color=REP_COLORS, alpha=0.8, edgecolor='black')
    ax4.set_xlabel('Repetition', fontweight='bold')
    ax4.set_ylabel('Mean Velocity', fontweight='bold')
    ax4.set_title('Mean Velocity', fontweight='bold')
    ax4.grid(True, alpha=0.3, axis='y')
    
    # Plot 5: Max Velocity
    ax5 = fig.add_subplot(gs[1, 1])
    ax5.bar(rep_nums, metrics['max_velocity'], color=REP_COLORS, alpha=0.8, edgecolor='black')
    ax5.set_xlabel('Repetition', fontweight='bold')
    ax5.set_ylabel('Max Velocity', fontweight='bold')
    ax5.set_title('Max Velocity', fontweight='bold')
    ax5.grid(True, alpha=0.3, axis='y')
    
    # Plot 6: Efficiency
    ax6 = fig.add_subplot(gs[1, 2])
    bars = ax6.bar(rep_nums, metrics['efficiency'], color=REP_COLORS, alpha=0.8, edgecolor='black')
    ax6.set_xlabel('Repetition', fontweight='bold')
    ax6.set_ylabel('Efficiency (%)', fontweight='bold')
    ax6.set_title('Path Efficiency', fontweight='bold')
    ax6.grid(True, alpha=0.3, axis='y')
    # Add value labels
    for bar, eff in zip(bars, metrics['efficiency']):
        height = bar.get_height()
        ax6.text(bar.get_x() + bar.get_width()/2., height,
                f'{eff:.1f}%', ha='center', va='bottom', fontsize=8, fontweight='bold')
    
    # Plot 7: Mean Jerk
    ax7 = fig.add_subplot(gs[2, 0])
    ax7.bar(rep_nums, metrics['mean_jerk'], color=REP_COLORS, alpha=0.8, edgecolor='black')
    ax7.set_xlabel('Repetition', fontweight='bold')
    ax7.set_ylabel('Mean Jerk', fontweight='bold')
    ax7.set_title('Movement Smoothness (Jerk)', fontweight='bold')
    ax7.grid(True, alpha=0.3, axis='y')
    
    # Plot 8: Mean Curvature
    ax8 = fig.add_subplot(gs[2, 1])
    ax8.bar(rep_nums, metrics['mean_curvature'], color=REP_COLORS, alpha=0.8, edgecolor='black')
    ax8.set_xlabel('Repetition', fontweight='bold')
    ax8.set_ylabel('Mean Curvature', fontweight='bold')
    ax8.set_title('Path Curvature', fontweight='bold')
    ax8.grid(True, alpha=0.3, axis='y')
    
    # Plot 9: Consistency Score (coefficient of variation)
    ax9 = fig.add_subplot(gs[2, 2])
    cv_scores = []
    for key in ['path_length', 'duration', 'max_deviation', 'efficiency']:
        cv = np.std(metrics[key]) / (np.mean(metrics[key]) + 1e-10)
        cv_scores.append(cv)
    
    metric_names = ['Path Length', 'Duration', 'Deviation', 'Efficiency']
    bars = ax9.bar(metric_names, cv_scores, color=['#FF6B6B', '#4ECDC4', '#45B7D1', '#FFA07A'],
                   alpha=0.8, edgecolor='black')
    ax9.set_ylabel('Coefficient of Variation', fontweight='bold')
    ax9.set_title('Consistency Across Repetitions\n(Lower = More Consistent)', fontweight='bold')
    ax9.grid(True, alpha=0.3, axis='y')
    # Add value labels
    for bar, cv in zip(bars, cv_scores):
        height = bar.get_height()
        ax9.text(bar.get_x() + bar.get_width()/2., height,
                f'{cv:.3f}', ha='center', va='bottom', fontsize=9, fontweight='bold')
    
    plt.suptitle('Comprehensive Metrics Dashboard', fontsize=20, fontweight='bold', y=0.995)
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    plt.close()
    print(f"✓ Saved: {output_file}")


def plot_temporal_evolution(points, repetitions, output_file):
    """Show how metrics evolve over the 10 repetitions"""
    fig, axes = plt.subplots(2, 2, figsize=(16, 12))
    
    # Calculate metrics
    path_lengths = []
    durations = []
    efficiencies = []
    mean_velocities = []
    
    for rep in repetitions:
        rep_points = rep['points']
        x = np.array([p['x'] for p in rep_points])
        y = np.array([p['y'] for p in rep_points])
        t = np.array([p['t'] for p in rep_points])
        data = calculate_kinematics(rep_points)
        
        segments = np.sqrt(np.diff(x)**2 + np.diff(y)**2)
        path_lengths.append(np.sum(segments))
        durations.append(t[-1] - t[0] if len(t) > 1 else 0)
        mean_velocities.append(np.mean(data['v_mag']))
        
        actual_length = np.sum(segments)
        straight_length = np.sqrt((x[-1] - x[0])**2 + (y[-1] - y[0])**2)
        efficiency = (straight_length / actual_length * 100) if actual_length > 0 else 0
        efficiencies.append(efficiency)
    
    rep_nums = np.arange(1, 11)
    
    # Plot 1: Path Length Evolution
    ax1 = axes[0, 0]
    ax1.plot(rep_nums, path_lengths, 'o-', linewidth=3, markersize=10, 
            color='#2E86AB', label='Path Length')
    ax1.fill_between(rep_nums, path_lengths, alpha=0.3, color='#2E86AB')
    # Add trend line
    z = np.polyfit(rep_nums, path_lengths, 1)
    p = np.poly1d(z)
    ax1.plot(rep_nums, p(rep_nums), '--', color='red', linewidth=2, 
            label=f'Trend: {"+" if z[0] > 0 else ""}{z[0]:.4f}/rep')
    ax1.set_xlabel('Repetition Number', fontweight='bold')
    ax1.set_ylabel('Path Length', fontweight='bold')
    ax1.set_title('Path Length Evolution', fontweight='bold')
    ax1.grid(True, alpha=0.3, linestyle='--')
    ax1.legend()
    
    # Plot 2: Duration Evolution
    ax2 = axes[0, 1]
    ax2.plot(rep_nums, durations, 'o-', linewidth=3, markersize=10,
            color='#A23B72', label='Duration')
    ax2.fill_between(rep_nums, durations, alpha=0.3, color='#A23B72')
    z = np.polyfit(rep_nums, durations, 1)
    p = np.poly1d(z)
    ax2.plot(rep_nums, p(rep_nums), '--', color='red', linewidth=2,
            label=f'Trend: {"+" if z[0] > 0 else ""}{z[0]:.4f}/rep')
    ax2.set_xlabel('Repetition Number', fontweight='bold')
    ax2.set_ylabel('Duration (s)', fontweight='bold')
    ax2.set_title('Duration Evolution', fontweight='bold')
    ax2.grid(True, alpha=0.3, linestyle='--')
    ax2.legend()
    
    # Plot 3: Efficiency Evolution
    ax3 = axes[1, 0]
    ax3.plot(rep_nums, efficiencies, 'o-', linewidth=3, markersize=10,
            color='#F18F01', label='Efficiency')
    ax3.fill_between(rep_nums, efficiencies, alpha=0.3, color='#F18F01')
    z = np.polyfit(rep_nums, efficiencies, 1)
    p = np.poly1d(z)
    ax3.plot(rep_nums, p(rep_nums), '--', color='red', linewidth=2,
            label=f'Trend: {"+" if z[0] > 0 else ""}{z[0]:.2f}%/rep')
    ax3.set_xlabel('Repetition Number', fontweight='bold')
    ax3.set_ylabel('Efficiency (%)', fontweight='bold')
    ax3.set_title('Efficiency Evolution', fontweight='bold')
    ax3.grid(True, alpha=0.3, linestyle='--')
    ax3.legend()
    
    # Plot 4: Mean Velocity Evolution
    ax4 = axes[1, 1]
    ax4.plot(rep_nums, mean_velocities, 'o-', linewidth=3, markersize=10,
            color='#C73E1D', label='Mean Velocity')
    ax4.fill_between(rep_nums, mean_velocities, alpha=0.3, color='#C73E1D')
    z = np.polyfit(rep_nums, mean_velocities, 1)
    p = np.poly1d(z)
    ax4.plot(rep_nums, p(rep_nums), '--', color='red', linewidth=2,
            label=f'Trend: {"+" if z[0] > 0 else ""}{z[0]:.4f}/rep')
    ax4.set_xlabel('Repetition Number', fontweight='bold')
    ax4.set_ylabel('Mean Velocity', fontweight='bold')
    ax4.set_title('Velocity Evolution', fontweight='bold')
    ax4.grid(True, alpha=0.3, linestyle='--')
    ax4.legend()
    
    plt.suptitle('Temporal Evolution: Learning/Adaptation Over Repetitions', 
                fontsize=18, fontweight='bold', y=0.995)
    plt.tight_layout()
    plt.savefig(output_file, dpi=300, bbox_inches='tight')
    plt.close()
    print(f"✓ Saved: {output_file}")


def main(json_file):
    """Main function to generate all visualizations"""
    print(f"\n{'='*60}")
    print(f"Advanced Hand-Nose Test Visualization")
    print(f"{'='*60}\n")
    
    print(f"Loading data from {json_file}...")
    points = load_data(json_file)
    points = normalize_timestamps(points)
    print(f"Loaded {len(points)} data points")
    
    print("\nIdentifying repetitions...")
    repetitions = identify_repetitions(points)
    print(f"✓ Identified {len(repetitions)} repetitions\n")
    
    # Generate base filename
    base_name = json_file.replace('.json', '').replace('tracked_index_fingers_', '')
    
    print("Generating advanced visualizations...\n")
    
    # Generate all plots
    plot_3d_trajectory_with_velocity(points, repetitions, 
                                     f'{base_name}_01_3d_trajectory.png')
    plot_trajectory_heatmap_overlay(points, repetitions, 
                                    f'{base_name}_02_heatmap_overlay.png')
    plot_velocity_vector_field(points, repetitions, 
                               f'{base_name}_03_velocity_vectors.png')
    plot_deviation_heatmap(points, repetitions, 
                           f'{base_name}_04_deviation_heatmap.png')
    plot_phase_space_velocity(points, repetitions, 
                             f'{base_name}_05_phase_space.png')
    plot_frequency_spectrum(points, repetitions, 
                           f'{base_name}_06_frequency_spectrum.png')
    plot_comprehensive_metrics_dashboard(points, repetitions, 
                                         f'{base_name}_07_metrics_dashboard.png')
    plot_temporal_evolution(points, repetitions, 
                           f'{base_name}_08_temporal_evolution.png')
    
    print(f"\n{'='*60}")
    print("All visualizations generated successfully!")
    print(f"{'='*60}\n")


if __name__ == "__main__":
    json_file = "tracked_index_fingers_1762919906.json"
    main(json_file)

