#!/usr/bin/env python3
"""
modtran_case_generator.py
    - Allows user to define a location, date and time, and source of radiance
    - uses Skyfield to compute the locations of the sun/moon at the specified date and time
    - computes relative azimuth/zenith of Sun/Moon w.r.t. user defined LOS
    - writes MODTRAN JSON file with each LOS case for solar/lunar radiance modelling 

Usage example (Edinburgh Jan 3 01:00 UTC, moon):
python modtran_case_generator.py `
--lat 55.91450119018555 --lon -3.3166000843048096 --alt_m 100 `
--year 2026 --month 1 --day 3 --hour 13.0 `
--zen_min 0 --zen_max 0 --zen_step 0 --azi_min 0 --azi_max 0 --azi_step 0 `
--wmin 100 --wmax 10000 --wstep 1 --fwhm 2.5 `
--source sun --slit gaussian --clouds none `
--word Transm --json_name HOGSWinter1pm_100to10000_zen0_azi0.json --out_csv summary.csv
"""
import argparse, json, math
from math import sin, cos, radians, degrees
import numpy as np
import pandas as pd

try:
    from skyfield.api import load, Topos
except Exception:
    raise SystemExit("skyfield not found. Install with: pip install skyfield numpy pandas skyfield")

# ---------- Geometry Functions ----------
def julian_day(year, month, day, hourUTC):
    # converts calendar time as: days since noon Jan 1, 4713 BC
    # hourUTC may be fractional (e.g. 1.5 = 01:30)
    Y = int(year); M = int(month); D = int(day)
    fr = float(hourUTC)
    if M <= 2:
        Y -= 1
        M += 12
    A = math.floor(Y/100)
    B = 2 - A + math.floor(A/4)
    day_frac = fr / 24.0
    JD = math.floor(365.25*(Y + 4716)) + math.floor(30.6001*(M + 1)) + D + day_frac + B - 1524.5
    return JD

def compute_gmst_deg(jd):
    # computes Greenwich Mean Sidereal Time (GMST)
    T = (jd - 2451545.0) / 36525.0
    gmst = 280.46061837 + 360.98564736629 * (jd - 2451545.0) + 0.000387933 * T**2 - (T**3) / 38710000.0
    return gmst % 360.0

def ra_to_deg(ra):
    # skyfield right ascension (RA) in hours converted to degrees
    return ra.hours * 15.0

def ra_dec_to_subpoint_lon(RA_deg, gmst_deg):
    # finds the longitude on Earth directly under the Sun or Moon
    sublon = (RA_deg - gmst_deg) % 360.0
    if sublon > 180.0:
        sublon -= 360.0
    return sublon

def altaz_to_vector(alt_deg, az_deg):
    # ENU topocentric frame, az measured degrees East of North (0=N,90=E)
    # vector: x = north, y = east, z = up
    a = radians(alt_deg); az = radians(az_deg)
    north = math.cos(a) * math.cos(az)              #           |cos(altitude)cos(azimuth)|
    east  = math.cos(a) * math.sin(az)              # vector =  |cos(altitude)sin(azimuth)|
    up    = math.sin(a)                             #           |       sin(azimuth)      |
    v = np.array([north, east, up], dtype=float)
    return v / np.linalg.norm(v)

def relative_az_zen_from_vectors(LOS_vec, body_vec):
    LOS = LOS_vec / np.linalg.norm(LOS_vec)
    B = body_vec / np.linalg.norm(body_vec)
    dotLB = np.clip(np.dot(LOS, B), -1.0, 1.0)
    rel_zen = math.degrees(math.acos(dotLB))

    # perpendicular component
    M_perp = B - np.dot(B, LOS) * LOS
    norm_M = np.linalg.norm(M_perp)
    if norm_M < 1e-9:
        rel_az = 0.0
        return rel_az, rel_zen
    M_perp = M_perp / norm_M

    # choose reference 'up' direction
    up = np.array([0.0, 0.0, 1.0])          # makes most sense to choose local variable up direction
    if abs(np.dot(up, LOS)) > 0.999:        # if LOS is vertical though then up-LOS=[0,0,0] which is of no use so use up=[0,1,0 instead]
        up = np.array([0.0, 1.0, 0.0])
    
    # find perpendicular of 'up'
    u = up - np.dot(up, LOS) * LOS          # 'up' is now the perpendicular component of 'up' with respect to LOS
    u = u / np.linalg.norm(u)               # normalise 'u'

    # find second axis
    v = np.cross(LOS, u)                    # 'v' is now the second axis perpendicular to 'up' where:   u is rel_az=0
    a = math.atan2(np.dot(M_perp, v), np.dot(M_perp, u))                                              # v is rel az=90
    rel_az = math.degrees(a) % 360.0        # use arctan2 for full 360 range (4 quandrants) for azimuth
    return rel_az, rel_zen

def ensure_range(name, val, low, high):
    if val < low or val > high:
        raise ValueError(f"{name} ({val}) out of range [{low},{high}]")
    
# -------- MODTRAN Mapping Functions --------
def map_cloud_model(cloud_key):
    cloud_mapping = {
        'none': "CLOUD_NONE",
        'clear': "CLOUD_NONE",
        'cumulus': "CLOUD_CUMULUS",
        'altostratus': "CLOUD_ALTOSTRATUS",
        'stratus': "CLOUD_STRATUS",
        'stratocumulus': "CLOUD_STRATOCUMULUS",
        'nimbostratus': "CLOUD_NIMBOSTRATUS",
        'rain_drizzle': "CLOUD_RAIN_DRIZZLE",
        'rain_light': "CLOUD_RAIN_LIGHT",
        'rain_moderate': "CLOUD_RAIN_MODERATE",
        'rain_heavy': "CLOUD_RAIN_HEAVY",
        'rain_extreme': "CLOUD_RAIN_EXTREME",
        'cirrus': "CLOUD_CIRRUS",
        'cirrus_thin': "CLOUD_CIRRUS_THIN",
    }
    aerosol_clouds = cloud_mapping.get(cloud_key)
    if aerosol_clouds is None:
        raise ValueError(f"Unknown cloud model: {cloud_key}")
    return aerosol_clouds

def map_aerosol_model(aerosol_key):
    aerosol_mapping = {
        'none': "AER_NONE",
        'clear': "AER_NONE",
        'rural': "AER_RURAL",
        'rural_dense': "AER_RURAL_DENSE",
        'maritime_navy': "AER_MARITIME_NAVY",
        'maritime': "AER_MARITIME",
        'urban': "AER_URBAN",
        'tropospheric': "AER_TROPOSPHERIC",
        'fog_advective': "AER_FOG_ADVECTIVE",
        'fog_radiative': "AER_FOG_RADIATIVE",
        'desert': "AER_DESERT",
    }
    aerosol_model = aerosol_mapping.get(aerosol_key)
    if aerosol_model is None:
        raise ValueError(f"Unknown aerosol model: {aerosol_key}")
    return aerosol_model

def map_stratospheric_model(straospheric_key):
    strato_mapping = {
        'background': "STRATO_BACKGROUND",
        'mod_volcanic_aged': "STRATO_MODERATE_VOLCANIC_AGED",
        'high_volcanic_fresh': "STRATO_HIGH_VOLCANIC_FRESH",
        'high_volcanic_aged': "STRATO_HIGH_VOLCANIC_AGED",
        'mod_volcanic_fresh': "STRATO_MODERATE_VOLCANIC_FRESH",
        'mod_volcanic_background': "STRATO_MODERATE_VOLCANIC_BACKGROUND",
        'high_volcanic_background': "STRATO_HIGH_VOLCANIC_BACKGROUND",
        'extreme_volcanic_fresh': "STRATO_EXTREME_VOLCANIC_FRESH",
    }
    strato_model = strato_mapping.get(straospheric_key)
    if strato_model is None:
        raise ValueError(f"Unknown stratospheric model: {straospheric_key}")
    return strato_model

# -------- Main Function --------
def generate_cases(args):
    # Parse array arguments
    lats = [float(l.strip()) for l in args.lat.split(',')]
    lons = [float(l.strip()) for l in args.lon.split(',')]
    alts = [float(a.strip()) for a in args.alt_m.split(',')]
    hours = [float(h.strip()) for h in args.hour.split(',')]
    sources = [s.strip() for s in args.source.split(',')]
    clouds_list = [c.strip() for c in args.clouds.split(',')]
    visib_list = [float(v.strip()) for v in args.visib_km.split(',')]
    aerosol_list = [a.strip() for a in args.aerosol_model.split(',')]
    strato_list = [a.strip() for a in args.strato_model.split(',')]

    # Ensure all arrays have the same length or length of 1
    # Broadcast single values to match max length
    max_len = max(len(lats), len(lons), len(alts), len(hours), len(sources), 
                  len(clouds_list), len(visib_list), len(aerosol_list), len(strato_list))
    
    def broadcast(lst, length):
        return lst * length if len(lst) == 1 else lst
    
    lats = broadcast(lats, max_len)
    lons = broadcast(lons, max_len)
    alts = broadcast(alts, max_len)
    hours = broadcast(hours, max_len)
    sources = broadcast(sources, max_len)
    clouds_list = broadcast(clouds_list, max_len)
    visib_list = broadcast(visib_list, max_len)
    aerosol_list = broadcast(aerosol_list, max_len)
    strato_list = broadcast(strato_list, max_len)

    if not (len(lats) == len(lons) == len(alts) == len(hours) == len(sources) == 
            len(clouds_list) == len(visib_list) == len(aerosol_list) == len(strato_list)):
        raise ValueError("Array arguments must all have the same length or be singular.")

    # Zenith/Azimuth check for -1 for a single case
    if args.zen_step == -1:
        zens = [args.zen_min]
    else:
        zens = np.arange(args.zen_min, args.zen_max + 1e-9, args.zen_step)
    if args.azi_step == -1:
        azis = [args.azi_min]
    else:
        azis = np.arange(args.azi_min, args.azi_max + 1e-9, args.azi_step)


    # Load Skyfield planetary ephemeris file
    eph = load('de421.bsp')                     # this file contains precise positions and motions of solar system bodies
    ts = load.timescale()                       # loads a timescale object

    # extract Earth, Sun, Moon objects
    earth = eph['earth']
    sun = eph['sun']
    moon = eph['moon']

    cases = []; rows = []; idx = 0

    # Track unique locations to assign location index
    unique_locations = []
    location_indices = []

    # Loop for counting number of locations used
    for param_idx, (lat, lon, alt_m, hour, source, clouds, visib_km, aerosol_model, strato_model) in enumerate(
    zip(lats, lons, alts, hours, sources, clouds_list, visib_list, aerosol_list, strato_list)):
    
        # Determine location index based on unique (lat, lon, alt_m) tuple
        loc_tuple = (lat, lon, alt_m)
        if loc_tuple not in unique_locations:
            unique_locations.append(loc_tuple)
        loc_idx = unique_locations.index(loc_tuple) + 1  # 1-indexed
        location_indices.append(loc_idx)

    # Loop over parameter sets
    for param_idx, (lat, lon, alt_m, hour, source, clouds, visib_km, aerosol_model, strato_model) in enumerate(
        zip(lats, lons, alts, hours, sources, clouds_list, visib_list, aerosol_list, strato_list)):
        # build Skyfield time (convert to hrs:min:sec)
        h_int = int(math.floor(hour))
        rem = (hour - h_int) * 60.0
        minute = int(math.floor(rem))
        second = int(round((rem - minute) * 60.0))
        t = ts.utc(int(args.year), int(args.month), int(args.day), h_int, minute, second) # Skyfield time object created for position calculations

        # JD (UTC) for GMST calculation
        jd_utc = julian_day(args.year, args.month, args.day, hour)
        gmst_deg = compute_gmst_deg(jd_utc)

        # Geocentric RA/Dec - compute the altitude and azimuth for sun and moon as seen from Earth
        sun_astrom = earth.at(t).observe(sun).apparent()            # creates Earth at specific time, computes vector from observer (Earth), 
        moon_astrom = earth.at(t).observe(moon).apparent()          # and corrects for light-time aberration for aparrent position
        RA_sun_deg = ra_to_deg(sun_astrom.radec()[0])
        Dec_sun_deg = sun_astrom.radec()[1].degrees
        RA_moon_deg = ra_to_deg(moon_astrom.radec()[0])
        Dec_moon_deg = moon_astrom.radec()[1].degrees

        # Compute lunar phase angle (phase=0 for full moon, phase = 90 for half moon, etc.)
        computed_lunar_phase_deg = moon_astrom.phase_angle(sun).degrees
        if source.lower().startswith('moon'):
            lunar_phase_deg = float(args.lun_phase) if args.lun_phase is not None else computed_lunar_phase_deg
            lunar_phase_source = "User defined" if args.lun_phase is not None else "Skyfield Calculated"
        else:
            lunar_phase_deg = None

        subsolar_lon = ra_dec_to_subpoint_lon(RA_sun_deg, gmst_deg)
        sublunar_lon = ra_dec_to_subpoint_lon(RA_moon_deg, gmst_deg)

        # topocentric alt/az at site (create a specific observer site on Earth)
        # (Skyfield returns az degrees East of North)
        site = earth + Topos(
            latitude_degrees=lat,
            longitude_degrees=lon,
            elevation_m=alt_m
        )
        topo_sun = site.at(t).observe(sun).apparent().altaz()
        topo_moon = site.at(t).observe(moon).apparent().altaz()
        alt_sun_deg, az_sun_deg = topo_sun[0].degrees, topo_sun[1].degrees
        alt_moon_deg, az_moon_deg = topo_moon[0].degrees, topo_moon[1].degrees
        zen_sun_deg = 90.0 - alt_sun_deg
        zen_moon_deg = 90.0 - alt_moon_deg

        if param_idx == 0:  # Print ephemeris for first parameter set only
            print("Ephemeris summary (first parameter set):")
            print(f"  UTC: {args.year}-{args.month:02d}-{args.day:02d} {hour}h")
            print(f"  Location: lat={lat:.6f}° lon={lon:.6f}° alt={alt_m:.1f}m")
            print(f"  Sun topocentric az={az_sun_deg:.4f}° zen={zen_sun_deg:.4f}° sub-lon={subsolar_lon:.4f} lat={Dec_sun_deg:.4f}")
            print(f"  Moon topocentric az={az_moon_deg:.4f}° zen={zen_moon_deg:.4f}° sub-lon={sublunar_lon:.4f} lat={Dec_moon_deg:.4f}")
            if source.lower().startswith('moon') and lunar_phase_deg is not None:
                print(f"  Lunar phase angle = {lunar_phase_deg:.3f}° ({lunar_phase_source})")
                print(f"  Lunar illuminated fraction = {((1+math.cos(radians(lunar_phase_deg)))/2*100):.3f}%")
            print()

        # Map cloud and aerosol models
        aerosol_clouds = map_cloud_model(clouds)
        aerosol_model_code = map_aerosol_model(aerosol_model)
        strato_model_code = map_stratospheric_model(strato_model)

        # --------------------------------------------------------------------------------------
        #   BUILDING MODTRAN JSON
        # --------------------------------------------------------------------------------------
        # default sections and arguqments
        default_rtoptions = {
            "MODTRN": "RT_CORRK_FAST", "LYMOLC": False, "T_BEST": False,
            "IMULT": "RT_DISORT_AT_OBS", "DISALB": True, "NSTR": 8, "SOLCON": 0.0
        }
        default_atmosphere = {"MODEL": "ATM_MIDLAT_WINTER", "M2_RHC": True, "CO2MX": 0.0}
        default_aerosols = {"IHAZE": aerosol_model_code, "IVULCN": strato_model_code, "ICLD": aerosol_clouds, "ISEASN": "SEASN_FALL_WINTER", "VIS": visib_km}
        default_surface = {"SURFTYPE": "REFL_LAMBER_MODEL", "NSURF": 1, "SURFP": {"CSALB": "LAMB_URBAN"}}
        default_spectral = {
            "V1": args.wmin, "V2": args.wmax, "DV": args.wstep, "FWHM": args.fwhm,
            "XFLAG": "N", "FLAGS": "NGAA  F", "MLFLX": -1, "LBMNAM": "T", "BMNAME": "p1_2013"
        }

        # Geometry loop
        for z in zens:
            for a in azis:
                idx += 1
                alt_los = 90.0 - z
                LOS_vec = altaz_to_vector(alt_los, a)

                # body vectors (topocentric)
                sun_vec = altaz_to_vector(alt_sun_deg, az_sun_deg)
                moon_vec = altaz_to_vector(alt_moon_deg, az_moon_deg)

                src = source.lower().strip()

                if src.startswith('sun'):
                    body_vec = sun_vec
                    iemsct_case = "RT_SOLAR_AND_THERMAL"
                    body_topo_az = az_sun_deg
                    body_topo_zen = zen_sun_deg
                    rel_az_deg, rel_zen_deg = relative_az_zen_from_vectors(LOS_vec, body_vec)

                elif src.startswith('none'):
                    iemsct_case = "RT_TRANSMITTANCE"
                    body_topo_az = None
                    body_topo_zen = None
                    rel_az_deg = None
                    rel_zen_deg = None

                else:
                    body_vec = moon_vec
                    iemsct_case = "RT_LUNAR_AND_THERMAL"
                    body_topo_az = az_moon_deg
                    body_topo_zen = zen_moon_deg
                    rel_az_deg, rel_zen_deg = relative_az_zen_from_vectors(LOS_vec, body_vec)

                # build geometry; PARM1 = rel az (deg), PARM2 = rel zen (deg)
                geom = {
                    "ITYPE": 3,
                    "H1ALT": alt_m / 1000.0,
                    "H2ALT": 0.0,
                    "OBSZEN": float(z),
                    "HRANGE": 0.0,
                    "BETA": float(a),
                    "BCKZEN": 0.0,
                    "IDAY": int(args.day),
                }

                if rel_az_deg is not None and rel_zen_deg is not None:
                    geom.update({
                        "IPARM": 2,
                        "PARM1": float(rel_az_deg),
                        "PARM2": float(rel_zen_deg),
                    })
                if source.lower().startswith('moon') and lunar_phase_deg is not None:
                    geom["ANGLEM"] = lunar_phase_deg

                # filename pattern used by MODTRAN outputs (CSVPRNT)
                visib_int = int(visib_km) if visib_km == int(visib_km) else visib_km
                filename_csv = f"{args.word}_loc{loc_idx}_{visib_int}kmvis_{clouds}_{aerosol_model}_{strato_model}_zen{int(round(z))}_azi{int(round(a))}.csv"
                name = f"{args.word}_loc{loc_idx}_{visib_int}kmvis_{clouds}_{aerosol_model}_{strato_model}_zen{int(round(z))}_azi{int(round(a))}"
                
                case = {
                    "MODTRANINPUT": {
                        "NAME": name,
                        "DESCRIPTION": f"Case {idx} - param_set {param_idx+1}, LOS zen {z} az {a}",
                        "CASE": idx,
                        "RTOPTIONS": {**default_rtoptions, "IEMSCT": iemsct_case},
                        "ATMOSPHERE": default_atmosphere,
                        "AEROSOLS": default_aerosols,
                        "GEOMETRY": geom,
                        "SURFACE": default_surface,
                        "SPECTRAL": default_spectral,
                        "FILEOPTIONS": {"CSVPRNT": filename_csv}
                    }
                }
                cases.append(case)

                rows.append({
                    "case_index": idx,
                    "param_set": param_idx+1,
                    "lat": lat,
                    "lon": lon,
                    "alt_m": alt_m,
                    "hour": hour,
                    "source": source,
                    "clouds": clouds,
                    "visib_km": visib_km,
                    "aerosol_model": aerosol_model,
                    "strato_model": strato_model,
                    "name": name,
                    "los_zen_deg": z,
                    "los_az_deg": a,
                    "rel_az_deg": rel_az_deg,
                    "rel_zen_deg": rel_zen_deg,
                    "body_topo_az_deg": body_topo_az,
                    "body_topo_zen_deg": body_topo_zen,
                    "csv": filename_csv
                })

    json_out = {"MODTRAN": cases}
    with open(args.json_name, "w") as f:
        json.dump(json_out, f, indent=2)
    df = pd.DataFrame(rows)
    df.to_csv(args.out_csv, index=False)

    print(f"Generated {len(cases)} cases.")
    print(f" - JSON written to: {args.json_name}")
    print(f" - CSV summary written to: {args.out_csv}")

# ---------- Main CLI ----------
def main():
    parser = argparse.ArgumentParser(description="Generate MODTRAN cases for solar or lunar radiance scans.")
    # Date-time
    parser.add_argument("--year", type=int, default=2026)
    parser.add_argument("--month", type=int, default=1)
    parser.add_argument("--day", type=int, default=3)
    parser.add_argument("--hour", type=str, default="1.0", help="UTC hour (fractional allowed), comma-separated for multiple (e.g., '1.0,13.0')")

    # location
    parser.add_argument("--lat", type=str, required=True, help="ground station latitude (deg N)")
    parser.add_argument("--lon", type=str, required=True, help="ground station longitude (deg East positive; West negative)")
    parser.add_argument("--alt_m", type=str, default="100.0", help="ground station altitude in meters")

    # LOS and Simulation Sweep parameters
    parser.add_argument("--zen_min", type=float, default=0.0); parser.add_argument("--zen_max", type=float, default=90.0); parser.add_argument("--zen_step", type=float, default=10.0)
    parser.add_argument("--azi_min", type=float, default=0.0); parser.add_argument("--azi_max", type=float, default=350.0); parser.add_argument("--azi_step", type=float, default=10.0)
    parser.add_argument("--wmin", type=float, default=500); parser.add_argument("--wmax", type=float, default=5000); parser.add_argument("--wstep", type=float, default=1.0)

    # Spectral parameters
    parser.add_argument("--fwhm", type=float, default=2.5)
    parser.add_argument("--source", default='moon', help="Extraterrestrial source - 'sun' or 'moon' or use 'none' for transmittance only.")
    parser.add_argument("--lun_phase", type=float, default=None, help="Lunar phase angle (0=Full, 90=Half, 180=New). Only use if --source is 'moon'. If omitted it is computed based on date-time")
    parser.add_argument("--slit", default='gaussian', help="slit function to be used by MODTRAN")
    parser.add_argument("--word", default="Transm", help="Word placed at beginning of the MODTRAN output files")

    # Output files
    parser.add_argument("--json_name", default="modtran_generated_cases.json",help="name of JSON file generated by the script to be used as input for MODTRAN")
    parser.add_argument("--out_csv", default="cases_summary.csv")

    # Atmospheric, Weather, Aerosol parameters
    parser.add_argument("--visib_km", type=str, default="10", help="Meterological visibility defined by Koschmieder's Law. Default is set to 10km.")
    parser.add_argument("--clouds", type=str, default="none", help="Cloud model type used by MODTRAN (options include: rain light, stratus, cirrus).")
    parser.add_argument("--aerosol_model", type=str, default="urban", help="Aerosol model used by MODTRAN.")
    parser.add_argument("--strato_model", type=str, default="background", help="Stratospheri model used by MODTRAN. (options include: background, high_volcanic_fresh, mod_volcanic_background, etc.)")
    args = parser.parse_args()
    generate_cases(args)

if __name__ == "__main__":
    main()