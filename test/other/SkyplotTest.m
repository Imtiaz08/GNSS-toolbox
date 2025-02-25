classdef SkyplotTest < matlab.unittest.TestCase
    properties
    end
    methods (TestClassSetup)
        function setupTest(obj)
            addpath(genpath('../../src'))
            close all
        end
    end
    methods (TestMethodTeardown)
        function closeFigures(obj)
            close all
        end
    end
    methods (Test)
        function testEmptySkyplot(obj)
            sp = Skyplot();
            title('Amazing skyplot');
            sp.exportToFile('sample0');
        end
        function testSkyplotBackground(obj)
            sp = Skyplot('skyplotTestBackground.png',10);
            sp.exportToFile('sample1'); % Create PNG
            sp.exportToFile('sample1','pdf'); % Create PDF
        end
        function testSkyplotWithLines(obj)
            sp = Skyplot();
            elev = linspace(0,60,100); azi = linspace(90,270,100);
            for i = 0:15:360
                sp.addPlot(elev,azi+i,sprintf('sat%.0f',i));
            end
            sp.exportToFile('sample2','pdf');
            sp.exportToFile('sample2','png');
        end
        function testSkyplotWithScatter(obj)
            sp = Skyplot();
            elev = linspace(0,60,100); azi = linspace(90,270,100);
            sp.addScatter(30,90,1);
            sp.addScatter(30,90,-1);
            %sp.addScatter(elev,azi,randn(size(elev)));
            %sp.addScatter(elev,azi+180,randn(size(elev)),10);
            %sp.exportToFile('sample3','pdf');
            %sp.exportToFile('sample3','png');
        end
        function testSkyplotWithLinesAndScatter(obj)
            sp = Skyplot();
            elev = linspace(0,60,100); azi = linspace(90,270,100);
            sp.addPlot(elev,azi,'sat1');
            sp.addScatter(elev,azi+90,randn(size(elev)));
            sp.addPlot(elev,azi+180,'sat2');
            sp.addScatter(elev,azi+270,randn(size(elev)),10);
            sp.exportToFile('sample4','pdf');
            sp.exportToFile('sample4','png');
        end
    end
end