function nv = structToNameValues(s)
    fn = fieldnames(s);
    nv = cell(1, 2*numel(fn));
    for k = 1:numel(fn)
        nv{2*k-1} = fn{k};
        nv{2*k}   = s.(fn{k});
    end
end