using System;
using System.Collections.Generic;
using System.Globalization;
using System.IO;

namespace PipEdgeKeeper
{
    internal sealed class AppSettings
    {
        private const int DefaultSnapDistance = 64;
        private const int DefaultPollMilliseconds = 150;

        public int SnapDistance { get; set; }
        public int PollMilliseconds { get; set; }
        public bool FlushEdges { get; set; }
        public bool UseMonitorBounds { get; set; }

        public AppSettings()
        {
            SnapDistance = DefaultSnapDistance;
            PollMilliseconds = DefaultPollMilliseconds;
            FlushEdges = true;
            UseMonitorBounds = true;
        }

        public static AppSettings Load()
        {
            AppSettings settings = new AppSettings();
            string path = GetSettingsPath();
            if (!File.Exists(path))
            {
                return settings;
            }

            try
            {
                Dictionary<string, string> values =
                    new Dictionary<string, string>(StringComparer.OrdinalIgnoreCase);

                foreach (string line in File.ReadAllLines(path))
                {
                    int separator = line.IndexOf('=');
                    if (separator <= 0)
                    {
                        continue;
                    }

                    values[line.Substring(0, separator).Trim()] =
                        line.Substring(separator + 1).Trim();
                }

                settings.SnapDistance = ReadInt(
                    values,
                    "SnapDistance",
                    DefaultSnapDistance,
                    0,
                    100);
                settings.PollMilliseconds = ReadInt(
                    values,
                    "PollMilliseconds",
                    DefaultPollMilliseconds,
                    50,
                    5000);
                settings.FlushEdges = ReadBool(values, "FlushEdges", true);
                settings.UseMonitorBounds =
                    ReadBool(values, "UseMonitorBounds", true);
            }
            catch
            {
                return new AppSettings();
            }

            return settings;
        }

        public void Save()
        {
            string path = GetSettingsPath();
            Directory.CreateDirectory(Path.GetDirectoryName(path));

            string[] lines =
            {
                "SnapDistance=" +
                    SnapDistance.ToString(CultureInfo.InvariantCulture),
                "PollMilliseconds=" +
                    PollMilliseconds.ToString(CultureInfo.InvariantCulture),
                "FlushEdges=" + FlushEdges.ToString(CultureInfo.InvariantCulture),
                "UseMonitorBounds=" +
                    UseMonitorBounds.ToString(CultureInfo.InvariantCulture)
            };

            File.WriteAllLines(path, lines);
        }

        private static string GetSettingsPath()
        {
            string directory = Path.Combine(
                Environment.GetFolderPath(
                    Environment.SpecialFolder.LocalApplicationData),
                "PipEdgeKeeper");
            return Path.Combine(directory, "settings.ini");
        }

        private static int ReadInt(
            IDictionary<string, string> values,
            string key,
            int fallback,
            int minimum,
            int maximum)
        {
            string value;
            int parsed;
            if (!values.TryGetValue(key, out value) ||
                !int.TryParse(
                    value,
                    NumberStyles.Integer,
                    CultureInfo.InvariantCulture,
                    out parsed))
            {
                return fallback;
            }

            return Math.Max(minimum, Math.Min(maximum, parsed));
        }

        private static bool ReadBool(
            IDictionary<string, string> values,
            string key,
            bool fallback)
        {
            string value;
            bool parsed;
            return values.TryGetValue(key, out value) &&
                   bool.TryParse(value, out parsed)
                ? parsed
                : fallback;
        }
    }
}
