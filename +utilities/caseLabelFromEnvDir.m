function label = caseLabelFromEnvDir(envDir)
% Create a short label from an environment directory string
envDir = string(envDir);
if contains(lower(envDir), "sun")
    label = "Day";
elseif contains(lower(envDir), "moon") || contains(lower(envDir), "lunar")
    label = "Night";
else
    label = "Case";
end
end