classdef Source
    % Source
    %
    % Transmitter source model containing key parameters for a QKD system.
    % Stores wavelength, repetition rate, state probabilities, and losses.
    %
    % Syntax:
    %   src = components.Source(wavelength, options)
    %
    % Additional options and defaults are given in the constructor.

    properties (SetAccess = protected)
        % Wavelength of the source (nm), set by the mounting platform.
        wavelength {mustBeScalarOrEmpty, mustBePositive}

        % Wavelength units (e.g., 'nano' for nm).
        units units.Magnitude

        % Number of photon pulses per second (Hz).
        repetition_rate {mustBeScalarOrEmpty, mustBeNonnegative} = 1e9

        % Transmitter power efficiency (fraction).
        efficiency {mustBeScalarOrEmpty, mustBePositive} = 1

        % Average photons per pulse for signal, vacuum, decoy.
        mpn_signal {mustBeNumeric, mustBeNonnegative} = 0.01
        mpn_vacuum {mustBeNumeric, mustBeNonnegative} = 0
        mpn_decoy  {mustBeNumeric, mustBeNonnegative} % optional

        % State preparation error fraction.
        state_prep_error {mustBeScalarOrEmpty, mustBeNonnegative} = 0.01

        % Normalised autocorrelation at zero delay (g2).
        g2 {mustBeScalarOrEmpty, mustBeNonnegative} = 0.01

        % Probabilities of emitting different states.
        probability_signal {mustBeNumeric, mustBeNonnegative, ...
            mustBeLessThanOrEqual(probability_signal, 1)}
        probability_decoy {mustBeNumeric, mustBeNonnegative, ...
            mustBeLessThanOrEqual(probability_decoy, 1)}

        % Loss between source and local receiver for entanglement protocols.
        local_loss {mustBeInRange(local_loss, 0, 1)} = 1

        % Per-source emission properties (overrides for beam modelling)
        emission_divergence = []          % full-angle divergence (radians). empty => use model/telescope fallback
        emission_beam_model = ""          % '' | 'airy' | 'truncated_gaussian' | 'flat_top'
        emission_truncation_ratio = []    % radius / waist (unitless), used for truncated_gaussian
        emission_beam_waist = []          % beam waist in metres (used as alternative to truncation ratio)
    end

    properties(Dependent)
        %probability of no photon sent
        probability_vacuum {mustBeNumeric, mustBeNonnegative, ...
            mustBeLessThanOrEqual(probability_vacuum, 1)}

        %overall mean photon number over decoy, signal and vacuum states
        overallMPN {mustBeNonnegative}
    end

    methods
        function obj = Source(wavelength, options)
            % Source constructor.
            %
            % Syntax:
            %   obj = Source(wavelength, options)
            %
            % Inputs:
            %   wavelength - (1,1) double, wavelength in given units
            %   options    - name-value arguments for other parameters
            %
            % Outputs:
            %   obj        - Source object

            arguments
                wavelength
                options.Wavelength_Scale units.Magnitude = "nano"
                options.Repetition_Rate = 1e9
                options.Efficiency = 1
                options.MPN_Signal = 0.01
                options.MPN_Decoy
                options.State_Prep_Error = 0.01
                options.g2 = 0.01
                options.Probability_Signal {mustBeNumeric, ...
                    mustBeNonnegative, ...
                    mustBeLessThanOrEqual(options.Probability_Signal, 1)} = 1
                options.Probability_Decoy {mustBeNumeric, ...
                    mustBeNonnegative, ...
                    mustBeLessThanOrEqual(options.Probability_Decoy, 1)}
                options.Local_Loss {mustBeInRange(options.Local_Loss, 0, 1)} = 1

                % emission settings (optional)
                options.Emission_Divergence = []
                options.Emission_Beam_Model = ""
                options.Emission_Truncation_Ratio = []
                options.Emission_Beam_Waist = []
            end

            % Map options into object properties
            for option = fieldnames(options)'
                opt = option{1};
                propName = matlab.lang.makeValidName(lower(opt));  % canonical property name
        
                switch opt
                    case 'Wavelength_Scale'
                        obj = obj.setWavelength(wavelength, "Wavelength_Scale", options.Wavelength_Scale);
                        continue
                    case 'Repetition_Rate'
                        obj = obj.setRepetitionRate(options.Repetition_Rate);
                        continue
                end

                % explicit mapping for emission options
                switch opt
                    case 'Emission_Divergence'
                        obj.emission_divergence = options.(opt);
                    case 'Emission_Beam_Model'
                        obj.emission_beam_model = options.(opt);
                    case 'Emission_Truncation_Ratio'
                        obj.emission_truncation_ratio = options.(opt);
                    case 'Emission_Beam_Waist'
                        obj.emission_beam_waist = options.(opt);
                end

               % generic mapping for other options: try lowercased property name
                if isprop(obj, propName)
                    obj.(propName) = options.(opt);
                else
                    % unknown option: ignore (preserves previous tolerant behaviour)
                end
            end
           
            % Validate emission options
            if ~isempty(obj.emission_divergence)
                if ~(isnumeric(obj.emission_divergence) && isreal(obj.emission_divergence) && obj.emission_divergence >= 0)
                    error('components.Source:BadEmissionDivergence', 'Emission_Divergence must be a nonnegative real scalar.');
                end
            end
            if ~isempty(obj.emission_truncation_ratio)
                if ~(isnumeric(obj.emission_truncation_ratio) && isreal(obj.emission_truncation_ratio) && obj.emission_truncation_ratio > 0)
                    error('components.Source:BadTruncationRatio', 'Emission_Truncation_Ratio must be a positive real scalar.');
                end
            end
            if ~isempty(obj.emission_beam_waist)
                if ~(isnumeric(obj.emission_beam_waist) && isreal(obj.emission_beam_waist) && obj.emission_beam_waist > 0)
                    error('components.Source:BadBeamWaist', 'Emission_Beam_Waist must be a positive real scalar.');
                end
            end
            if ~isempty(obj.emission_beam_model) && obj.emission_beam_model ~= ""
                if ~ismember(obj.emission_beam_model, ["airy","truncated_gaussian","flat_top",""])
                    error('components.Source:BadBeamModel', 'Emission_Beam_Model must be one of: "" | airy | truncated_gaussian | flat_top');
                end
            end
        end

        function p_vacuum = get.probability_vacuum(obj)
            % updateVacuumProbability
            %
            % Calculate and set the vacuum state probability based on the
            % configured signal and (optionally) decoy state probabilities.
            % If the decoy probability is not set, vacuum is simply
            % 1 − probability_signal.

            arguments
                obj
            end

            if isempty(obj.probability_decoy)
                p_vacuum = 1 - obj.probability_signal;
                return
            end

            total_probability = obj.probability_signal + obj.probability_decoy;

            if total_probability > 1
                error('probabilities of signal and decoy must not sum to more than 1');
            end

            p_vacuum = 1 - total_probability;
        end

        function mpn = get.overallMPN(source)
            % calculates the mean photon number over all decoy and signal
            % states, if these are present. if not, returns the signal mpn.
            % this represents the overall mean number of photons out of the
            % source per pulse
            arguments
                source (1,1) components.Source
            end
            
            if ~isempty(source.mpn_decoy)&&~isempty(source.probability_decoy)
                mpn = source.probability_signal * source.mpn_signal + ...
                    source.probability_decoy * source.mpn_decoy;
            else
                mpn = source.mpn_signal;
            end
        end

        function obj = setWavelength(obj, wavelength, options)
            % setWavelength
            %
            % Set the wavelength (nm) of the source.
            %
            % Syntax:
            %   obj = setWavelength(obj, wavelength, options)
            %
            % Inputs:
            %   wavelength - (1,1) double, wavelength to set
            %   options    - struct with field Wavelength_Scale
            %
            % Outputs:
            %   obj        - updated Source object

            arguments
                obj
                wavelength
                options.Wavelength_Scale units.Magnitude = "nano"
            end

            obj.wavelength = units.Magnitude.convert( ...
                options.Wavelength_Scale, "nano", wavelength);
            obj.units = options.Wavelength_Scale;
        end


        function obj = setRepetitionRate(obj, repetition_rate)
            % setRepetitionRate
            %
            % Set the repetition rate (Hz) of the source.

            obj.repetition_rate = repetition_rate;
        end


        function obj = setEfficiency(obj, efficiency)
            % setEfficiency
            %
            % Set the transmitter/source efficiency (fraction).

            obj.efficiency = efficiency;
        end


        function obj = setMeanPhotonNumber(obj, state, mean_photon_number)
            % setMeanPhotonNumber
            %
            % Set the mean photon number for the given state.
            %
            % Inputs:
            %   state              - 'Signal' or 'Decoy'
            %   mean_photon_number - nonnegative double

            arguments
                obj
                state {mustBeMember(state, {"Signal", "Decoy"})}
                mean_photon_number {mustBeNumeric, mustBeNonnegative}
            end

            switch state
                case "Signal"
                    obj.mpn_signal = mean_photon_number;
                case "Decoy"
                    obj.mpn_decoy = mean_photon_number;
            end
        end


        function obj = setStateProbabilities(obj, state, probability)
            % setStateProbabilities
            %
            % Set the probability of a given state and update the vacuum
            % probability accordingly.
            %
            % Inputs:
            %   state       - 'Signal' or 'Decoy'
            %   probability - (1,1) double in [0,1]

            arguments
                obj
                state {mustBeMember(state, {"Signal", "Decoy"})}
                probability {mustBeNumeric, mustBeNonnegative, ...
                    mustBeLessThanOrEqual(probability, 1)}
            end

            switch state
                case "Signal"
                    obj.probability_signal = probability;
                case "Decoy"
                    obj.probability_decoy = probability;
            end

            obj = obj.updateVacuumProbability();
        end


        function obj = setg2(obj, g2_value)
            % setg2
            %
            % Set the g2 value for the source.

            obj.g2 = g2_value;
        end


        function obj = setStatePrepError(obj, state_prep_error)
            % setStatePrepError
            %
            % Set the probability of preparing a quantum state incorrectly.

            obj.state_prep_error = state_prep_error;
        end

        function obj = setEmissionBeamModel(obj, model)
            arguments
                obj
                model {mustBeMember(model, ["", "airy", "truncated_gaussian", "flat_top"])}
            end
            obj.emission_beam_model = model;
        end

        function obj = setEmissionTruncationRatio(obj, tr)
            arguments
                obj
                tr {mustBeNonnegative}
            end
            obj.emission_truncation_ratio = tr;
        end

        function obj = setEmissionBeamWaist(obj, w)
            arguments
                obj
                w {mustBeNonnegative}
            end
            obj.emission_beam_waist = w;
        end

        function div = getEmissionDivergence(obj, telescope)
            % getEmissionDivergence Return full-angle divergence in radians
            %   1) explicit emission_divergence (full-angle)
            %   2) emission_beam_model == 'truncated_gaussian' (uses telescope helper)
            %   3) fallback to telescope.FOV
            arguments
                obj components.Source
                telescope components.Telescope
            end

            % 1) explicitdivergence override
            if ~isempty(obj.emission_divergence) && ~isnan(obj.emission_divergence)
                div = obj.emission_divergence;
                return
            end

            % 2) model-based calculations
            if ~isempty(obj.emission_beam_model) && obj.emission_beam_model ~= ""
                switch char(obj.emission_beam_model)
                    case 'truncated_gaussian'
                        if ~isempty(obj.emission_beam_waist) && ~isnan(obj.emission_beam_waist)
                            div = telescope.ComputeDivergenceForModel('truncated_gaussian', 'BeamWaist', obj.emission_beam_waist);
                            return
                        elseif ~isempty(obj.emission_truncation_ratio) && ~isnan(obj.emission_truncation_ratio)
                            div = telescope.ComputeDivergenceForModel('truncated_gaussian', 'TruncationRatio', obj.emission_truncation_ratio);
                            return
                        else
                            error('components.Source:MissingTruncation', 'Set emission_truncation_ratio or emission_beam_waist for truncated_gaussian.');
                        end
                    case 'airy'
                        div = telescope.ComputeDivergenceForModel('airy');
                        return
                    case 'flat_top'
                        div = telescope.ComputeDivergenceForModel('flat_top');
                        return
                    otherwise
                        error('components.Source:UnknownBeamModel', 'Unknown emission_beam_model "%s".', obj.emission_beam_model);
                end
            end

            % 3) fallback to telescope FOV
            div = telescope.fov;
        end
    
    end
end