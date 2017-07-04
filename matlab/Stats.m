classdef Stats < handle
  %STATS Summary of this class goes here
  %   Detailed explanation goes here
  
  properties
    names = {}
    accumulators = []
    counts = []
    lastValues = []
    fromNetwork = []
    
    smoothenPlots = 0
    
    lookup = struct()
    history = struct()
  end
  
  properties (Transient)
    varIdx = []
    plots = []
  end
  
  methods
    function o = Stats(names, varargin)
      % parse arguments
      vl_parseprop(o, varargin, {'smoothenPlots'}) ;
      
      % initialize with given stat names
      assert(iscellstr(names)) ;
      o.names = names ;
      o.accumulators = zeros(size(names)) ;
      o.counts = zeros(size(names)) ;
      o.lastValues = zeros(size(names)) ;
      o.varIdx = zeros(size(names)) ;
      o.fromNetwork = true(size(names)) ;
      
      % name-to-index lookup table
      for i = 1:numel(names)
        o.lookup.(names{i}) = i ;
      end
    end
    
    function update(o, varargin)
      if isa(varargin{1}, 'Net')
        o.update_net(varargin{1}) ;
        varargin(1) = [] ;
      end
      
      assert(mod(numel(varargin), 2) == 0, 'Expected name-value pairs.') ;
      assert(iscellstr(varargin(1:2:end-1)), 'Expected name-value pairs.') ;
      
      for i = 1:2:numel(varargin)
        o.update_single(varargin{i}, varargin{i + 1}) ;
      end
    end
    
    function v = value(o, name)
      idx = o.lookup.(name) ;
      v = o.accumulators(idx) / o.counts(idx) ;
    end
    
    function reset(o)
      o.accumulators(:) = 0 ;
      o.counts(:) = 0 ;
      o.lastValues(:) = 0 ;
    end
    
    function push(o, set)
      % push current stats into history and reset
      if ~isfield(o.history, set)
        o.history.(set) = [] ;
      end
      o.history.(set)(:,end+1) = o.accumulators ./ o.counts ;
      o.reset() ;
    end
    
    function print(o)
      % print statistics to the terminal
      for i = 1:numel(o.names)
        if o.counts(i) > 0
          name = o.names{i} ;
          v = o.lastValues(i) ;
          avg = o.accumulators(i) / o.counts(i) ;
          if abs(v) < 1e-3 && v ~= 0
            fprintf('%s: %.0e ', name, v) ;
          else
            fprintf('%s: %.3f ', name, v) ;
          end
          if abs(avg) < 1e-3 && avg ~= 0
            fprintf('(avg %.0e) ', avg) ;
          else
            fprintf('(avg %.3f) ', avg) ;
          end
        end
      end
      fprintf('\n') ;
    end
    
    function plot(o, varargin)
      opts.figure = 1 ;
      opts.names = [] ;
      opts.smoothen = 0 ;
      opts = vl_argparse(opts, varargin) ;
      
      if isempty(opts.names)
        valid_stats = 1:numel(o.names) ;
      else
        valid_stats = find(ismember(o.names, opts.names)) ;
      end
      
      sets = fieldnames(o.history) ;
      
      % create plot objects if it's the first datapoint to be plotted, or
      % the graphics objects have been deleted
      if size(o.history.(sets{1}), 2) == 1 || isempty(o.plots) || ~all(ishandle(o.plots(:)))
        figure(opts.figure) ; clf ;
        ax = gobjects(numel(valid_stats), 1) ;
        o.plots = gobjects(numel(valid_stats), numel(sets)) ;
        
        for i = 1:numel(valid_stats)
          ax(i) = axes() ;
          o.plots(i,:) = plot(NaN(2, numel(sets)), '.-', 'Parent', ax(i)) ;
          
          name = o.names{valid_stats(i)} ;
          xlabel('Epoch') ;
          title(name) ;
          legend(sets{:}) ;
          grid on ;
        end
        
        dynamic_subplot(ax) ;
      end
      
      % smoothing kernel
      if opts.smoothen > 0
        window = fspecial('gaussian', [1, ceil(2 * opts.smoothen + 1)], opts.smoothen) ;
        n = size(o.history.(sets{1}), 2);
        normalization = conv(ones(1, n), window, 'same');
      end
      
      % update plots
      for i = 1:numel(valid_stats)
        for s = 1:numel(sets)
          v = o.history.(sets{s})(valid_stats(i),:) ;
          if opts.smoothen > 0
            v = conv(v, window, 'same') ./ normalization;
          end
          set(o.plots(i,s), 'XData', (1:numel(v))', 'YData', v');
        end
      end
      
      drawnow ;
    end
  end
  
  methods (Access = protected)
    function update_net(o, net)
      if isempty(o.varIdx)
        o.varIdx = zeros(size(o.names)) ;
      end
      
      for i = find(o.fromNetwork)
        name = o.names{i} ;
        if o.varIdx(i) == 0  % cache variable index
          o.varIdx(i) = net.getVarIndex(name) ;
        end
        
        % get average of tensor values (possibly from GPU)
        v = net.getValue(o.varIdx(i)) ;
        v = gather(sum(v(:))) / numel(v) ;
        o.lastValues(i) = v ;
        
        % accumulate
        o.accumulators(i) = o.accumulators(i) + v ;
        o.counts(i) = o.counts(i) + 1 ;
      end
    end
    
    function update_single(o, name, v)
      if ~isfield(o.lookup, name)
        o.names{end+1} = name ;
        o.lookup.(name) = numel(o.names) ;
        
        o.accumulators(end+1) = 0 ;
        o.counts(end+1) = 0 ;
        o.lastValues(end+1) = 0 ;
        o.varIdx(end+1) = 0 ;
        o.fromNetwork(end+1) = false ;
      end
      
      idx = o.lookup.(name) ;
      v = gather(sum(v(:))) / numel(v) ;
      o.lastValues(idx) = v ;
      o.accumulators(idx) = o.accumulators(idx) + v ;
      o.counts(idx) = o.counts(idx) + 1 ;
    end
  end
  
end

